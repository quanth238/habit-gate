import Testing
import Foundation
@testable import GateCore

@Suite(.serialized) struct PolicyTests {
    func calendar(_ zone: String = "Asia/Ho_Chi_Minh") -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!; return c
    }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    let sample = Habit(id: "a", name: "Review English vocabulary")
    func evaluate(_ status: String, now: Date? = nil) -> GateSnapshot {
        PolicyEngine.evaluate(policy: .init(habitIDs: ["a"]), habits: [sample], journal: [.init(id: "a", status: status)],
                              now: now ?? date("2026-10-18T07:00:00Z"), calendar: calendar())
    }
    @Test func testOnlyCompletedUnlocks() {
        for status in ["inprogress", "skipped", "failed", "unknown", "", "complete"] { expectEqual(evaluate(status).access, "blocked", status) }
        expectEqual(evaluate("completed").access, "allowed")
    }
    @Test func testEveryEssentialIsRequired() {
        let s = PolicyEngine.evaluate(policy: .init(habitIDs: ["a", "b"]), habits: [sample, .init(id: "b", name: "Read")],
            journal: [.init(id: "a", status: "completed"), .init(id: "b", status: "inprogress")], now: date("2026-10-18T07:00:00Z"), calendar: calendar())
        expectEqual(s.access, "blocked"); expectEqual(s.remainingCount, 1); expectEqual(s.completedCount, 1)
    }
    @Test func testUndoRelocks() { expectEqual(evaluate("completed").access, "allowed"); expectEqual(evaluate("inprogress").access, "blocked") }
    @Test func testFourAMBoundary() {
        let c = calendar(), before = date("2026-10-17T20:59:59Z"), after = date("2026-10-17T21:00:00Z")
        expectEqual(HabitDay(now: before, calendar: c).date, "2026-10-17")
        expectEqual(HabitDay(now: after, calendar: c).date, "2026-10-18")
        expectEqual(HabitDay(now: before, calendar: c).end, after)
        expectEqual(HabitDay(now: date("2026-10-17T17:00:00Z"), calendar: c).date, "2026-10-17")
    }
    @Test func testOfflineProofExpiresAtBoundary() {
        let c = calendar(), now = date("2026-10-17T20:00:00Z")
        let s = evaluate("completed", now: now)
        expectTrue(s.valid(at: now.addingTimeInterval(100), calendar: c))
        expectEqual(s.sanitized(at: s.expiresAt, calendar: c).access, "blocked")
        expectEqual(s.sanitized(at: now.addingTimeInterval(-60), calendar: c).access, "blocked")
    }
    @Test func testTimeZoneChangeInvalidatesProof() {
        let now = date("2026-10-18T07:00:00Z"), s = evaluate("completed")
        expectFalse(s.valid(at: now, calendar: calendar("America/New_York")))
    }
    @Test func testDSTBoundaryUsesCalendarDays() {
        let c = calendar("America/New_York")
        let spring = HabitDay(now: date("2026-03-07T17:00:00Z"), calendar: c)
        expectEqual(spring.end.timeIntervalSince(spring.start), 23 * 3600)
        let fall = HabitDay(now: date("2026-10-31T17:00:00Z"), calendar: c)
        expectEqual(fall.end.timeIntervalSince(fall.start), 25 * 3600)
    }
    @Test func testSchedules() throws {
        let c = calendar(); var h = sample
        h.occurrence = .init(type: "weekDays", days: [0]) // 18 October is Sunday.
        expectTrue(try PolicyEngine.due(h, on: "2026-10-18", calendar: c))
        expectFalse(try PolicyEngine.due(h, on: "2026-10-19", calendar: c))
        h.occurrence = .init(type: "monthDays", days: [18, 31])
        expectTrue(try PolicyEngine.due(h, on: "2026-10-18", calendar: c))
        h.startDate = "2026-10-16"; h.occurrence = .init(type: "interval", interval: 2)
        expectTrue(try PolicyEngine.due(h, on: "2026-10-18", calendar: c))
        expectFalse(try PolicyEngine.due(h, on: "2026-10-19", calendar: c))
        h.occurrence = .init(type: "weekDays", days: [8]); expectThrows(try PolicyEngine.due(h, on: "2026-10-18", calendar: c))
    }
    @Test func testRestDayRequiresValidSelectedHabits() {
        var h = sample; h.occurrence = .init(type: "weekDays", days: [1])
        let s = PolicyEngine.evaluate(policy: .init(habitIDs: ["a"]), habits: [h], journal: [], now: date("2026-10-18T07:00:00Z"), calendar: calendar())
        expectEqual(s.access, "allowed"); expectEqual(s.dueCount, 0)
        let empty = PolicyEngine.evaluate(policy: .init(habitIDs: []), habits: [h], journal: [], now: date("2026-10-18T07:00:00Z"), calendar: calendar())
        expectEqual(empty.access, "blocked")
    }
    @Test func testMissingArchivedWeeklyAndBadHabitsStayBlocked() {
        var archived = sample; archived.isArchived = true
        var weekly = sample; weekly.goals = [.init(periodicity: "weekly")]
        var bad = sample; bad.type = "bad"
        for habits in [[], [archived], [weekly], [bad]] {
            let s = PolicyEngine.evaluate(policy: .init(habitIDs: ["a"]), habits: habits, journal: [.init(id: "a", status: "completed")],
                                         now: date("2026-10-18T07:00:00Z"), calendar: calendar())
            expectEqual(s.access, "blocked"); expectEqual(s.habits.first?.status, "configuration")
        }
    }
    @Test func testMissingOrDuplicateJournalEntryCannotUnlock() {
        for journal: [JournalEntry] in [[], [.init(id: "a", status: "completed"), .init(id: "a", status: "completed")]] {
            expectEqual(PolicyEngine.evaluate(policy: .init(habitIDs: ["a"]), habits: [sample], journal: journal,
                now: date("2026-10-18T07:00:00Z"), calendar: calendar()).access, "blocked")
        }
    }
    @Test func testDomainValidationAndBoundaries() throws {
        expectEqual(try DomainRules.normalize(" *.Facebook.COM. "), "facebook.com")
        for domain in ["https://facebook.com", "x.com/path", "x.com:443", "localhost", "127.0.0.1", "x..com", "-x.com", "app.habitify.me"] {
            expectThrows(try DomainRules.normalize(domain), domain)
        }
        expectTrue(DomainRules.matches(host: "m.facebook.com", domain: "facebook.com"))
        expectFalse(DomainRules.matches(host: "notfacebook.com", domain: "facebook.com"))
        expectFalse(DomainRules.matches(host: "facebook.com.evil.test", domain: "facebook.com"))
    }
    @Test func testAtomicSnapshotRoundtripAndPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let s = evaluate("completed")
        try GateFiles.write(s, "snapshot.json", root: root)
        expectEqual(GateFiles.read(GateSnapshot.self, "snapshot.json", root: root)?.access, "allowed")
        let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("snapshot.json").path)
        expectEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data("bad json".utf8).write(to: root.appendingPathComponent("snapshot.json"))
        expectNil(GateFiles.read(GateSnapshot.self, "snapshot.json", root: root))
    }
    @Test func testPolicyEditsCannotUnlockBeforeTheNextBoundary() {
        let c = calendar(), now = date("2026-10-17T20:00:00Z")
        let first = Policy(habitIDs: ["a", "b"]), easier = Policy(habitIDs: ["a"])
        var config = Configuration(); config.stage(first, now: now, calendar: c)
        expectEqual(config.active, first)
        config.stage(easier, now: now, calendar: c)
        expectEqual(config.active, first)
        config.advance(now: date("2026-10-17T20:59:59Z"), calendar: c); expectEqual(config.active, first)
        config.advance(now: date("2026-10-17T21:00:00Z"), calendar: c); expectEqual(config.active, easier)
        expectNil(config.pending)
    }
    @Test func testPendingPolicyRebasesSafelyAfterTimezoneChange() {
        let now = date("2026-10-18T07:00:00Z")
        var config = Configuration(active: .init(habitIDs: ["a", "b"]))
        config.stage(.init(habitIDs: ["a"]), now: now, calendar: calendar())
        config.advance(now: now, calendar: calendar("America/New_York"))
        expectEqual(config.active?.habitIDs, ["a", "b"])
        expectEqual(config.pending?.effectiveAt, HabitDay(now: now, calendar: calendar("America/New_York")).end)
    }
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(lhs == rhs, Comment(rawValue: message), sourceLocation: sourceLocation)
}
private func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value, sourceLocation: sourceLocation) }
private func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!value, sourceLocation: sourceLocation) }
private func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value == nil, sourceLocation: sourceLocation) }
private func expectThrows<T>(_ operation: @autoclosure () throws -> T, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try operation(); Issue.record(Comment(rawValue: "Expected error: " + message), sourceLocation: sourceLocation) } catch { }
}
