import Foundation
import Testing
@testable import GateCore

struct WeekendScheduleTests {
    let app = BlockedApp(bundleID: "com.example.chat", name: "Chat")
    func date(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }
    func calendar(_ zone: String = "Asia/Ho_Chi_Minh") -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!; return c
    }
    func configuration() -> Configuration {
        var c = Configuration(active: .init(habitIDs: ["read"], apps: [app])); c.weekendsOff = true; return c
    }
    @Test func weekendsUseTheExistingFourAMHabitDay() {
        for (raw, allowed) in [("2026-10-23T17:00:00Z", false), ("2026-10-23T20:59:59Z", false),
                               ("2026-10-23T21:00:00Z", true), ("2026-10-24T17:00:00Z", true),
                               ("2026-10-25T20:59:59Z", true), ("2026-10-25T21:00:00Z", false),
                               ("2026-10-26T05:00:00Z", false)] {
            #expect((WeekendSchedule.snapshot(configuration: configuration(), cached: nil, now: date(raw), calendar: calendar()) != nil) == allowed)
        }
    }
    @Test func offlineDayOffRequiresNoHabitifyProofOrCatalogAndNeverCompletesHabits() throws {
        let now = date("2026-10-24T05:00:00Z")
        let snapshot = try #require(WeekendSchedule.snapshot(configuration: configuration(), cached: nil, now: now, calendar: calendar()))
        #expect(snapshot.isWeekendDayOff); #expect(snapshot.valid(at: now, calendar: calendar()))
        #expect(snapshot.dueCount == 0); #expect(snapshot.completedCount == 0)
        #expect(snapshot.habits.first?.status == "notDue"); #expect(snapshot.lastHabitifySyncedAt == nil)
        #expect(snapshot.verificationSource == "weekendSchedule"); #expect(snapshot.syncError == nil)
        #expect(!AppRules.shouldBlock(bundleID: app.bundleID, apps: [app], snapshot: snapshot, now: now, calendar: calendar()))
    }
    @Test func existingInstallsAndUnconfiguredAppsDoNotGainAWeekendByDefault() throws {
        let old = try GateFiles.decoder().decode(Configuration.self, from: Data(#"{"active":{"habitIDs":["read"],"domains":["x.com"]},"notifyOnUnlock":false}"#.utf8))
        let now = date("2026-10-24T05:00:00Z")
        #expect(old.weekendsOff == nil)
        #expect(WeekendSchedule.snapshot(configuration: old, cached: nil, now: now, calendar: calendar()) == nil)
        var empty = Configuration(); empty.weekendsOff = true
        #expect(WeekendSchedule.snapshot(configuration: empty, cached: nil, now: now, calendar: calendar()) == nil)
    }
    @Test func aCurrentLocalProofIsReusedAndTheRealAPITimestampIsPreserved() throws {
        let now = date("2026-10-24T05:00:00Z"), realSync = date("2026-10-23T06:00:00Z")
        var cached = GateSnapshot.locked(now: now, calendar: calendar()); cached.lastSyncedAt = realSync
        let first = try #require(WeekendSchedule.snapshot(configuration: configuration(), cached: cached, now: now, calendar: calendar()))
        #expect(first.lastHabitifySyncedAt == realSync)
        let reused = WeekendSchedule.snapshot(configuration: configuration(), cached: first, now: now.addingTimeInterval(30), calendar: calendar())
        #expect(reused == first)
        let sunday = try #require(WeekendSchedule.snapshot(configuration: configuration(), cached: first, now: date("2026-10-25T05:00:00Z"), calendar: calendar()))
        #expect(sunday.habitDate == "2026-10-25"); #expect(sunday.lastHabitifySyncedAt == realSync)
    }
    @Test func disablingTheSettingOrStartingMondayDiscardsTheLocalUnlock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let saturday = date("2026-10-24T05:00:00Z"), monday = date("2026-10-25T21:00:00Z")
        var config = configuration(); try ConfigurationRepository.save(config, root: root)
        let proof = try #require(WeekendSchedule.snapshot(configuration: config, cached: nil, now: saturday, calendar: calendar()))
        #expect(!proof.valid(at: monday, calendar: calendar()))
        #expect(ConfigurationRepository.snapshot(for: ConfigurationRepository.load(root: root), cached: proof, now: monday, calendar: calendar()).access == "blocked")
        config.weekendsOff = nil; try ConfigurationRepository.save(config, root: root)
        #expect(ConfigurationRepository.snapshot(for: ConfigurationRepository.load(root: root), cached: proof, now: saturday, calendar: calendar()).access == "blocked")
    }
    @Test func recoveryAndTimezoneChangesDoNotReuseAWeekendUnlock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = date("2026-10-24T05:00:00Z")
        try ConfigurationRepository.save(configuration(), root: root)
        let proof = try #require(WeekendSchedule.snapshot(configuration: configuration(), cached: nil, now: now, calendar: calendar()))
        #expect(!proof.valid(at: now, calendar: calendar("America/New_York")))
        try Data("bad json".utf8).write(to: root.appendingPathComponent("configuration.json"))
        let loaded = ConfigurationRepository.load(root: root)
        #expect(loaded.needsRecovery)
        #expect(ConfigurationRepository.snapshot(for: loaded, cached: proof, now: now, calendar: calendar()).access == "blocked")
    }
}
