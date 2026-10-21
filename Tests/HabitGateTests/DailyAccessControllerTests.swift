import Foundation
import Testing
import GateCore
@testable import HabitGate

@Suite(.serialized) @MainActor struct DailyAccessControllerTests {
    final class Clock {
        var date = ISO8601DateFormatter().date(from: "2026-10-21T05:00:00Z")!
        var seconds = 100.0
        func advance(_ value: Double) { date = date.addingTimeInterval(value); seconds += value }
    }
    let apps: Set<String> = ["com.example.chat", "com.example.meeting"]
    func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func calendar() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!; return c }
    func controller(_ root: URL, _ clock: Clock) -> DailyAccessController {
        DailyAccessController(root: root, now: { clock.date }, continuous: { clock.seconds }, calendar: calendar, schedulesActions: false)
    }
    func begin(_ access: DailyAccessController, foreground: String? = nil) {
        access.refresh(foreground: nil, configured: apps, normalAccess: false, recovery: false)
        #expect(access.startAccess())
        access.refresh(foreground: foreground, configured: apps, normalAccess: false, recovery: false)
    }
    @Test func foregroundCountsSwitchingAwayPausesAndAppsShareDailyBalance() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        access.refresh(foreground: nil, configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 900); #expect(!access.isCounting); #expect(access.grant() == nil)
        #expect(access.startAccess()); #expect(access.grant() != nil)
        c.advance(120); #expect(access.remaining == 900)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        #expect(access.isCounting)
        c.advance(200); #expect(access.remaining == 700)
        access.refresh(foreground: "com.example.meeting", configured: apps, normalAccess: false, recovery: false)
        c.advance(100)
        access.refresh(foreground: "com.apple.finder", configured: apps, normalAccess: false, recovery: false)
        #expect(!access.isCounting); #expect(access.remaining == 600)
        c.advance(600); #expect(access.remaining == 600)
        access.verifyStorage(); #expect(access.issue.isEmpty)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        c.advance(600)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 0); #expect(access.grant() == nil)
        access.refresh(foreground: "com.example.meeting", configured: apps, normalAccess: false, recovery: false)
        #expect(access.grant() == nil)
    }
    @Test func restartPreservesPausedBalanceAndChargesUnfinishedForegroundSegment() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        begin(access, foreground: "com.example.chat")
        c.advance(120)
        let restored = controller(root, c)
        #expect(restored.remaining == 780); #expect(!restored.isCounting); #expect(!restored.accessStarted)
        c.advance(300)
        #expect(controller(root, c).remaining == 780)
    }
    @Test func saveFailureCannotGrantAndChangingSettingsDoesNotRefillToday() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); var fail = false; var writes = 0
        let access = DailyAccessController(root: root, now: { c.date }, continuous: { c.seconds }, calendar: calendar,
            save: { _ in if fail { throw CocoaError(.fileWriteUnknown) }; writes += 1 }, schedulesActions: false)
        fail = true
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        #expect(!access.startAccess())
        #expect(!access.isCounting); #expect(access.grant() == nil)
        fail = false
        access.retryStorage(); #expect(access.issue.isEmpty); #expect(access.remaining == 900)
        let clean = controller(root, c)
        begin(clean, foreground: "com.example.chat")
        c.advance(800); clean.refresh(foreground: nil, configured: apps, normalAccess: false, recovery: false)
        #expect(clean.setMinutes(60)); #expect(clean.remaining == 100); #expect(clean.budget.todayMinutes == 15)
        #expect(clean.budget.limitMinutes == 60)
        #expect(!clean.setMinutes(121))
        #expect(writes == 2)
    }
    @Test func resetAtFourAppliesNewLimitAndTimezoneDoesNotRefillEarly() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); c.date = ISO8601DateFormatter().date(from: "2026-10-21T20:59:00Z")!
        var zone = calendar()
        let access = DailyAccessController(root: root, now: { c.date }, continuous: { c.seconds }, calendar: { zone }, schedulesActions: false)
        #expect(access.setMinutes(5))
        begin(access, foreground: "com.example.chat")
        c.advance(30)
        zone.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 870); #expect(access.budget.todayMinutes == 15)
        zone = calendar(); c.advance(30)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        #expect(access.budget.todayMinutes == 5); #expect(access.remaining == 300)
        #expect(!access.accessStarted); #expect(access.grant() == nil)
        #expect(access.startAccess())
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        c.advance(10); #expect(access.remaining == 290)
    }
    @Test func sleepLockRecoveryOfflineAndHabitUnlock() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        begin(access, foreground: "com.example.chat")
        c.advance(100); access.suspend(); c.advance(3600)
        #expect(access.remaining == 800)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false, suspended: true)
        #expect(!access.isCounting)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        #expect(access.grant() != nil) // Network failure does not affect this local balance.
        c.advance(10)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: true, recovery: false)
        #expect(!access.isCounting); #expect(access.grant() == nil); #expect(access.remaining == 790)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: true)
        #expect(access.grant() == nil)
    }
    @Test func clockRollbackMissingAndMalformedStateFailClosed() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        begin(access, foreground: "com.example.chat")
        c.advance(20); c.date = c.date.addingTimeInterval(-10)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        #expect(access.grant() == nil); #expect(!access.issue.isEmpty)
        let url = root.appendingPathComponent(DailyAccessFile.name)
        try FileManager.default.removeItem(at: url); access.verifyStorage()
        #expect(access.grant() == nil)
        try Data("{bad".utf8).write(to: url)
        let restored = controller(root, c)
        #expect(restored.remaining == 0); #expect(!restored.issue.isEmpty)
    }
    @Test func noPerSecondDiskWritesAndOneMinuteWarning() {
        let root = root(); let c = Clock(); var writes = 0
        let access = DailyAccessController(root: root, now: { c.date }, continuous: { c.seconds }, calendar: calendar,
            save: { _ in writes += 1 }, schedulesActions: false)
        begin(access, foreground: "com.example.chat")
        for _ in 0..<20 {
            c.advance(1); access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        }
        #expect(writes == 3)
        c.advance(820); access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        #expect(access.notice.contains("One minute")); #expect(writes == 3)
    }
    @Test func manualStartAndEndNeverRefillTheDailyBalance() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        c.advance(60)
        #expect(!access.isCounting); #expect(access.grant() == nil); #expect(access.remaining == 900)
        #expect(access.startAccess()); #expect(!access.startAccess())
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        c.advance(120); access.endAccess()
        #expect(access.remaining == 780); #expect(!access.accessStarted); #expect(access.grant() == nil)
        access.refresh(foreground: "com.example.chat", configured: apps, normalAccess: false, recovery: false)
        c.advance(300); #expect(access.remaining == 780)
        #expect(access.startAccess())
        access.refresh(foreground: "com.example.meeting", configured: apps, normalAccess: false, recovery: false)
        c.advance(780)
        access.refresh(foreground: "com.example.meeting", configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 0); #expect(!access.accessStarted)
        #expect(!access.startAccess()); access.endAccess(); #expect(access.remaining == 0)
    }

}
