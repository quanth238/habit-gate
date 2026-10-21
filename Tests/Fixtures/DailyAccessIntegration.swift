// macOS integration harness. Compile with AppBlocker, DailyAccessController and
// GateCore. Launch the disposable me.habitgate.testfixture app through the UI.
import AppKit
import GateCore

@MainActor final class CountingFixture: GuardedApplication {
    let app: NSRunningApplication
    var hideCalls = 0
    init(_ app: NSRunningApplication) { self.app = app }
    var bundleIdentifier: String? { app.bundleIdentifier }
    var isHidden: Bool { app.isHidden }
    var isActive: Bool { app.isActive }
    var isTerminated: Bool { app.isTerminated }
    var isFinishedLaunching: Bool { app.isFinishedLaunching }
    func hide() -> Bool { hideCalls += 1; return app.hide() }
}
@MainActor final class DailyIntegrationDelegate: NSObject, NSApplicationDelegate {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("daily-access-integration-\(UUID())")
    let target = BlockedApp(bundleID: "me.habitgate.testfixture", name: "Disposable fixture")
    var controller: DailyAccessController!
    var captured: CountingFixture?
    var wasVisibleDuringGrant = false
    lazy var blocker = AppBlocker(running: { [weak self] in
        guard let app = self?.captureFixture() else { return [] }; return [app]
    }, frontmost: { NSWorkspace.shared.frontmostApplication })
    func captureFixture() -> CountingFixture? {
        if let captured { return captured }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first else { return nil }
        let wrapper = CountingFixture(app); captured = wrapper; return wrapper
    }
    var simulated: Bool { CommandLine.arguments.contains("--simulated-foreground") }
    var notices = 0
    var started = false
    var finished = false
    var watchdog: Timer?
    func applicationDidFinishLaunching(_ note: Notification) {
        var fixtureBudget = DailyAccessBudget(now: Date(), minutes: 1)
        fixtureBudget.usedSeconds = 55 // Five seconds remain; do not spend a real user’s allowance.
        try! DailyAccessFile.save(fixtureBudget, root: root)
        controller = DailyAccessController(root: root)
        controller.onChange = { [weak self] in self?.apply() }
        blocker.onForeground = { [weak self] id in
            guard let self else { return }
            if self.simulated { return }
            self.controller.refresh(foreground: id, configured: [self.target.id], normalAccess: false, recovery: false)
            self.apply()
        }
        blocker.onBlocked = { [weak self] _ in self?.notices += 1 }
        controller.refresh(foreground: nil, configured: [target.id], normalAccess: false, recovery: false)
        precondition(controller.startAccess())
        controller.refresh(foreground: simulated ? target.id : nil, configured: [target.id], normalAccess: false, recovery: false)
        blocker.start(); apply()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in self?.finish(error: "Timed out waiting for five seconds of foreground use") }
        print("Ready: open the disposable fixture, leave it foreground for five seconds."); fflush(stdout)
    }
    func apply() {
        blocker.update(apps: [target], snapshot: .locked(), allowance: controller.grant())
        if controller.isCounting {
            started = true
            if captureFixture()?.isHidden == false { wasVisibleDuringGrant = true }
        }
    }
    func check() {
        guard started, controller.remaining <= 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.finish() }
    }
    func finish(error: String? = nil) {
        guard !finished else { return }; finished = true
        let fixture = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first
        // Repeated state refreshes must not create another hide/notice cycle.
        apply(); apply()
        let checks = ["foreground_timer_started": started, "window_was_visible_during_grant": wasVisibleDuringGrant, "hide_called_once": captured?.hideCalls == 1, "shared_minute_exhausted": controller.remaining == 0,
                      "window_hidden": fixture?.isHidden == true, "process_preserved": fixture?.isTerminated == false,
                      "no_duplicate_notice": notices <= 1, "grant_revoked": controller.grant() == nil]
        let passed = error == nil && checks.values.allSatisfy { $0 }
        let result: [String: Any] = ["passed": passed, "checks": checks, "notices": notices, "simulated_foreground": simulated, "error": error ?? ""]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
        try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
        try? FileManager.default.removeItem(at: root)
        exit(passed ? 0 : 1)
    }
}
@main @MainActor struct DailyIntegrationMain {
    static func main() {
        let app = NSApplication.shared; let delegate = DailyIntegrationDelegate()
        app.delegate = delegate; app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
