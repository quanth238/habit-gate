import AppKit
import GateCore

@MainActor protocol GuardedApplication {
    var bundleIdentifier: String? { get }
    var isHidden: Bool { get }
    var isActive: Bool { get }
    var isTerminated: Bool { get }
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
    private var checking = Set<String>()
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
                let isLaunch = note.name == NSWorkspace.didLaunchApplicationNotification
                Task { @MainActor in
                    // Launch precedes the first activation on some apps. Let the activation
                    // event explain a foreground launch instead of hiding it too early.
                    if !isLaunch || app.isActive { self?.enforce(app, showNotice: true) }
                }
            })
        }
    }
    func update(apps: [BlockedApp], snapshot: GateSnapshot, now: Date = Date(), calendar: Calendar = .current) {
        let changed = self.apps != apps
        self.apps = apps; self.snapshot = snapshot
        if changed { verified.formIntersection(Set(apps.map(\.id))); onVerified?(verified); issues = issues.filter { key, _ in apps.contains { $0.id == key } }; reportIssues() }
        let blocking = !apps.isEmpty && (snapshot.access != "allowed" || !snapshot.valid(at: now, calendar: calendar))
        if blocking && (changed || !wasBlocking) {
            for app in running() { enforce(app, now: now, calendar: calendar) }
        } else if blocking, let app = frontmost() {
            enforce(app, now: now, calendar: calendar)
        } else if !blocking { issues.removeAll(); reportIssues() }
        wasBlocking = blocking
    }
    func enforce(_ app: any GuardedApplication, showNotice: Bool = false, now: Date = Date(), calendar: Calendar = .current) {
        guard !app.isTerminated,
              AppRules.shouldBlock(bundleID: app.bundleIdentifier, apps: apps, snapshot: snapshot, now: now, calendar: calendar),
              let target = apps.first(where: { $0.id == app.bundleIdentifier?.lowercased() }) else { return }
        if app.isHidden {
            if showNotice { onBlocked?(target) }
            return
        }
        let notify = showNotice || app.isActive
        if app.hide() {
            verified.insert(target.id); onVerified?(verified)
            issues.removeValue(forKey: target.id); reportIssues()
            if notify { onBlocked?(target) }
        } else {
            guard checking.insert(target.id).inserted else { return }
            // RunningApplication caches state for a run-loop turn. Verify after that turn
            // before treating a concurrent activation/hide request as a real failure.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.verifyHide(app, target: target, notify: notify, attempt: 0)
            }
        }
    }
    private func verifyHide(_ app: any GuardedApplication, target: BlockedApp, notify: Bool, attempt: Int) {
        guard !app.isTerminated,
              AppRules.shouldBlock(bundleID: app.bundleIdentifier, apps: apps, snapshot: snapshot) else {
            checking.remove(target.id); return
        }
        if app.isHidden {
            verified.insert(target.id); onVerified?(verified)
            checking.remove(target.id); issues.removeValue(forKey: target.id)
            if notify { onBlocked?(target) }
            reportIssues()
        } else if attempt < 2 {
            // Some apps begin activating before they can accept hide requests.
            // Retry twice during that launch transition, then expose a real failure.
            _ = app.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.verifyHide(app, target: target, notify: notify, attempt: attempt + 1)
            }
        } else {
            checking.remove(target.id)
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
