import AppKit
import SwiftUI
import GateCore
import Darwin

@main @MainActor struct HabitGateMain {
    private static var retainedDelegate: AppDelegate?
    static func main() {
        // Launch Services can briefly retain an exited app during an update.
        // Only another live process is a duplicate; return before starting AppKit.
        let anotherInstance = NSRunningApplication.runningApplications(withBundleIdentifier: "me.habitgate.app").contains {
            $0.processIdentifier != getpid() && !$0.isTerminated && kill($0.processIdentifier, 0) == 0
        }
        guard !anotherInstance else { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate; app.setActivationPolicy(.accessory)
        app.finishLaunching()
        delegate.startIfNeeded()
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var store: GateStore!
    private var status: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var blockedAppWindow: NSWindow?
    private var started = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        startIfNeeded()
    }
    func startIfNeeded() {
        guard !started else { return }
        started = true
        store = GateStore()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.target = self; status.button?.action = #selector(togglePopover)
        popover.behavior = .transient; popover.delegate = self
        store.showToday = { [weak self] in self?.settingsWindow?.close(); self?.togglePopover() }
        store.showSettings = { [weak self] in self?.openSettings() }
        store.statusChanged = { [weak self] in self?.updateStatus() }
        store.showBlockedApp = { [weak self] in self?.openBlockedApp() }
        store.start(); updateStatus()
        if store.configuration.active == nil { openSettings() }
    }
    private func updateStatus() {
        let allowed = store.snapshot.access == "allowed"
        status.button?.image = NSImage(systemSymbolName: allowed ? "lock.open" : "lock.shield", accessibilityDescription: allowed ? "Distractions unlocked" : "Distractions blocked")
        status.button?.title = store.configuration.active == nil ? " Set up" : allowed ? " Ready" :
            store.snapshot.habits.isEmpty ? " Checking" : " \(store.snapshot.remainingCount) left"
        status.button?.toolTip = "Habit Gate · \(store.snapshot.reason)"
    }
    @objc private func togglePopover() {
        guard let button = status.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            store.tick()
            popover.contentViewController = NSHostingController(rootView: TodayView(store: store))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Habit Gate"; window.isReleasedWhenClosed = false; window.delegate = self
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.minSize = NSSize(width: 880, height: 680); window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func openBlockedApp() {
        // The observed store can update an existing notice without activating it
        // again for another launch/unhide event in the same foreground attempt.
        guard blockedAppWindow?.isVisible != true else { return }
        popover.performClose(nil)
        if blockedAppWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Habit Gate · Essentials first"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: BlockedMacAppView(store: store, dismiss: { [weak self] in
                self?.blockedAppWindow?.close()
            }))
            window.center(); blockedAppWindow = window
        }
        blockedAppWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.contentView = nil
        if window === settingsWindow { settingsWindow = nil }
        if window === blockedAppWindow { blockedAppWindow = nil }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
}
