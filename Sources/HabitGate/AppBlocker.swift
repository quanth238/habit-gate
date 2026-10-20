import AppKit
import GateCore

@MainActor protocol GuardedApplication {
    var bundleIdentifier: String? { get }
    var isHidden: Bool { get }
    var isActive: Bool { get }
    var isTerminated: Bool { get }
    var isFinishedLaunching: Bool { get }
    @discardableResult func hide() -> Bool
}
extension NSRunningApplication: GuardedApplication {}

// Observe application events; never terminate apps or inspect their content.
@MainActor final class AppBlocker {
    var onBlocked: ((BlockedApp) -> Void)?
    var onIssue: ((String) -> Void)?
    var onVerified: ((Set<String>) -> Void)?
    private var verified = Set<String>()
    private let running: () -> [any GuardedApplication]
    private let frontmost: () -> (any GuardedApplication)?
    private var apps: [BlockedApp] = []
    private var snapshot = GateSnapshot.locked()
    private var wasBlocking = false
    private var observers: [NSObjectProtocol] = []
    private var issues: [String: String] = [:]
    private final class HideRequest {
        var notify: Bool
        var started = false
        init(notify: Bool) { self.notify = notify }
    }
    private var checking: [String: HideRequest] = [:]
    init(running: @escaping () -> [any GuardedApplication] = { NSWorkspace.shared.runningApplications },
         frontmost: @escaping () -> (any GuardedApplication)? = { NSWorkspace.shared.frontmostApplication }) {
        self.running = running; self.frontmost = frontmost
    }
    func start() {
        guard observers.isEmpty else { return }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                // Capture foreground intent before the asynchronous handler: a
                // successful hide may change isActive before this task runs.
                let showNotice = note.name != NSWorkspace.didLaunchApplicationNotification || app.isActive
                Task { @MainActor in
                    self?.enforce(app, showNotice: showNotice)
                }
            })
        }
    }
    func update(apps: [BlockedApp], snapshot: GateSnapshot, now: Date = Date(), calendar: Calendar = .current) {
        let changed = self.apps != apps
        self.apps = apps; self.snapshot = snapshot
        if changed {
            let selected = Set(apps.map(\.id))
            verified.formIntersection(selected); onVerified?(verified)
            checking = checking.filter { selected.contains($0.key) }
            issues = issues.filter { selected.contains($0.key) }; reportIssues()
        }
        let blocking = !apps.isEmpty && (snapshot.access != "allowed" || !snapshot.valid(at: now, calendar: calendar))
        if blocking && (changed || !wasBlocking) {
            for app in running() { enforce(app, now: now, calendar: calendar) }
        } else if blocking, let app = frontmost() {
            enforce(app, now: now, calendar: calendar)
        } else if !blocking { checking.removeAll(); issues.removeAll(); reportIssues() }
        wasBlocking = blocking
    }
    func enforce(_ app: any GuardedApplication, showNotice: Bool = false, now: Date = Date(), calendar: Calendar = .current) {
        guard !app.isTerminated,
              AppRules.shouldBlock(bundleID: app.bundleIdentifier, apps: apps, snapshot: snapshot, now: now, calendar: calendar),
              let target = apps.first(where: { $0.id == app.bundleIdentifier?.lowercased() }) else { return }
        let notify = showNotice || app.isActive
        let request: HideRequest
        if let pending = checking[target.id] {
            pending.notify = pending.notify || notify
            guard !pending.started else { return }
            request = pending
        } else {
            // Ignore stale hidden events after confirmation, but retain genuine
            // foreground intent delivered while a quiet hide is still pending.
            guard !app.isHidden else { return }
            request = HideRequest(notify: notify)
            checking[target.id] = request
        }
        // Zalo activates before it can reliably accept a hide. Its didLaunch
        // event resumes this request without polling or spending retries early.
        guard app.isFinishedLaunching else { return }
        request.started = true
        if !app.isHidden { _ = app.hide() }
        // Even a successful hide can have cached visibility until the next run-loop
        // turn. Confirm it once before presenting or activating the notice window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.verifyHide(app, target: target, request: request, attempt: 0)
        }
    }
    private func verifyHide(_ app: any GuardedApplication, target: BlockedApp, request: HideRequest, attempt: Int) {
        // An unlock/removal cancels this request. Its delayed callback cannot
        // consume or retry a newer hide operation for the same selected app.
        guard checking[target.id] === request else { return }
        guard !app.isTerminated,
              AppRules.shouldBlock(bundleID: app.bundleIdentifier, apps: apps, snapshot: snapshot) else {
            checking.removeValue(forKey: target.id); return
        }
        if app.isHidden {
            verified.insert(target.id); onVerified?(verified)
            checking.removeValue(forKey: target.id); issues.removeValue(forKey: target.id)
            if request.notify { onBlocked?(target) }
            reportIssues()
        } else if attempt < 2 {
            // Some apps begin activating before they can accept hide requests.
            // Retry twice during that launch transition, then expose a real failure.
            _ = app.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.verifyHide(app, target: target, request: request, attempt: attempt + 1)
            }
        } else {
            checking.removeValue(forKey: target.id)
            verified.remove(target.id); onVerified?(verified)
            issues[target.id] = "Could not hide \(target.name). Mac app protection needs attention."
            reportIssues()
        }
    }
    private func reportIssues() { onIssue?(issues.keys.sorted().compactMap { issues[$0] }.joined(separator: " ")) }
}

enum MacAppCatalog {
    static func app(at url: URL) -> BlockedApp? {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier, AppRules.selectable(id) else { return nil }
        let name = [bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                    bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                    url.deletingPathExtension().lastPathComponent].compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }!
        return BlockedApp(bundleID: id, name: name)
    }
    static func installed() -> [BlockedApp] {
        var found: [String: BlockedApp] = [:]
        for directory in FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask]) {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in urls {
                if let app = app(at: url) { found[app.id] = app }
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
