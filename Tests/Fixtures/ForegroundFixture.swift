import AppKit
@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Habit Gate test fixture"; window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
@main @MainActor struct FixtureMain {
    static func main() {
        let app = NSApplication.shared; let delegate = FixtureDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
