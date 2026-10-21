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
    func begin(_ access: DailyAccessController) {
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.startAccess())
        access.refresh(configured: apps, normalAccess: false, recovery: false)
    }
    @Test func startImmediatelyCountsContinuouslyAndAllAppsShareOneDailyBalance() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 900); #expect(!access.isCounting); #expect(access.grant() == nil)
        #expect(access.startAccess()); #expect(access.grant() != nil)
        #expect(access.isCounting)
        c.advance(120); #expect(access.remaining == 780)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.isCounting)
        c.advance(200); #expect(access.remaining == 580)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        c.advance(100)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.isCounting); #expect(access.remaining == 480)
        // Neither unrelated foreground apps nor an idle desktop pause the clock.
        c.advance(300); #expect(access.remaining == 180)
        access.verifyStorage(); #expect(access.issue.isEmpty)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        c.advance(180)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 0); #expect(access.grant() == nil)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.grant() == nil)
    }
    @Test func restartPreservesBalanceAndChargesAnUnfinishedCountdown() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        begin(access)
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
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(!access.startAccess())
        #expect(!access.isCounting); #expect(access.grant() == nil)
        fail = false
        access.retryStorage(); #expect(access.issue.isEmpty); #expect(access.remaining == 900)
        let clean = controller(root, c)
        begin(clean)
        c.advance(800); clean.refresh(configured: apps, normalAccess: false, recovery: false)
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
        begin(access)
        c.advance(30)
        zone.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 870); #expect(access.budget.todayMinutes == 15)
        zone = calendar(); c.advance(30)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.budget.todayMinutes == 5); #expect(access.remaining == 300)
        #expect(!access.accessStarted); #expect(access.grant() == nil)
        #expect(access.startAccess())
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        c.advance(10); #expect(access.remaining == 290)
    }
    @Test func sleepConsumesTimeAndOfflineRecoveryAndHabitUnlockKeepTheirRules() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        begin(access)
        c.advance(100); c.advance(300) // mach_continuous_time includes sleep/lock.
        #expect(access.remaining == 500)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.isCounting)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.grant() != nil) // Network failure does not affect this local balance.
        c.advance(10)
        access.refresh(configured: apps, normalAccess: true, recovery: false)
        #expect(!access.isCounting); #expect(access.grant() == nil); #expect(access.remaining == 490)
        access.refresh(configured: apps, normalAccess: false, recovery: true)
        #expect(access.grant() == nil)
    }
    @Test func clockRollbackMissingAndMalformedStateFailClosed() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        begin(access)
        c.advance(20); c.date = c.date.addingTimeInterval(-10)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
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
        begin(access)
        for _ in 0..<20 {
            c.advance(1); access.refresh(configured: apps, normalAccess: false, recovery: false)
        }
        #expect(writes == 2)
        c.advance(820); access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.notice.contains("One minute")); #expect(writes == 2)
    }
    @Test func manualStartAndEndNeverRefillTheDailyBalance() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        c.advance(60)
        #expect(!access.isCounting); #expect(access.grant() == nil); #expect(access.remaining == 900)
        #expect(access.startAccess()); #expect(!access.startAccess())
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        c.advance(120); access.endAccess()
        #expect(access.remaining == 780); #expect(!access.accessStarted); #expect(access.grant() == nil)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        c.advance(300); #expect(access.remaining == 780)
        #expect(access.startAccess())
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        c.advance(780)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 0); #expect(!access.accessStarted)
        #expect(!access.startAccess()); access.endAccess(); #expect(access.remaining == 0)
    }
    @Test func expiryRevokesAccessWithoutForegroundEventsOrPolling() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        var budget = DailyAccessBudget(now: Date())
        budget.usedSeconds = 899.8
        try DailyAccessFile.save(budget, root: root)
        let access = DailyAccessController(root: root)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        var expirations = 0
        access.onChange = { if !access.accessStarted { expirations += 1 } }
        #expect(access.startAccess())
        try await Task.sleep(for: .milliseconds(500))
        #expect(access.remaining == 0); #expect(!access.accessStarted)
        #expect(access.grant() == nil); #expect(expirations == 1)
        #expect(DailyAccessFile.load(root: root)?.usedSeconds == 900)
    }
    @Test func failedEndSaveRevokesAccessAndRetryDoesNotRefundSpentTime() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); var fail = false
        let access = DailyAccessController(root: root, now: { c.date }, continuous: { c.seconds }, calendar: calendar,
            save: { value in
                if fail { throw CocoaError(.fileWriteUnknown) }
                try DailyAccessFile.save(value, root: root)
            }, schedulesActions: false)
        begin(access); c.advance(90); fail = true; access.endAccess()
        #expect(access.grant() == nil); #expect(!access.accessStarted)
        #expect(access.remaining == 810); #expect(!access.issue.isEmpty)
        fail = false; access.retryStorage()
        #expect(access.issue.isEmpty); #expect(access.remaining == 810)
        #expect(controller(root, c).remaining == 810)
    }
    @Test func configurationRecoveryEndsRunningCountdownWithoutLosingBalance() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let c = Clock(); let access = controller(root, c)
        begin(access); c.advance(75)
        access.refresh(configured: apps, normalAccess: false, recovery: true)
        #expect(access.grant() == nil); #expect(!access.accessStarted)
        #expect(access.remaining == 825)
        c.advance(120)
        access.refresh(configured: apps, normalAccess: false, recovery: false)
        #expect(access.remaining == 825); #expect(access.grant() == nil)
    }

}
