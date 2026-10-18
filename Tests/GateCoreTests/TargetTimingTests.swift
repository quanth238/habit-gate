import Foundation
import Testing
@testable import GateCore

struct TargetTimingTests {
    let discord = BlockedApp(bundleID: "com.hnc.Discord", name: "Discord")
    let telegram = BlockedApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram")
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!; return c
    }
    var now: Date { ISO8601DateFormatter().date(from: "2026-10-18T07:00:00Z")! }
    @Test func additionsApplyWithoutActivatingTomorrowsHabits() {
        var c = Configuration(active: .init(habitIDs: ["today"], domains: ["x.com"], apps: [discord]))
        c.stage(.init(habitIDs: ["tomorrow"], domains: ["x.com", "messenger.com"], apps: [discord, telegram]), now: now, calendar: calendar)
        #expect(c.active?.habitIDs == ["today"])
        #expect(Set(c.active?.domains ?? []) == ["x.com", "messenger.com"])
        #expect(Set(c.active?.apps.map(\.id) ?? []) == [discord.id, telegram.id])
        #expect(c.pending?.policy.habitIDs == ["tomorrow"])
    }
    @Test func aMixedSaveAddsNowAndRemovesOnlyAtFourAM() {
        let old = Policy(habitIDs: ["a"], domains: ["x.com"], apps: [discord])
        let desired = Policy(habitIDs: ["a"], domains: ["instagram.com"], apps: [telegram])
        var c = Configuration(active: old)
        c.stage(desired, now: now, calendar: calendar)
        #expect(Set(c.active?.domains ?? []) == ["x.com", "instagram.com"])
        #expect(Set(c.active?.apps.map(\.id) ?? []) == [discord.id, telegram.id])
        let boundary = HabitDay(now: now, calendar: calendar).end
        c.advance(now: boundary.addingTimeInterval(-1), calendar: calendar)
        #expect(c.active?.apps.contains(discord) == true)
        c.advance(now: boundary, calendar: calendar)
        #expect(c.active == desired); #expect(c.pending == nil)
    }
    @Test func removingATargetJustAddedDoesNotCreateAPause() {
        var c = Configuration(active: .init(habitIDs: ["a"], domains: ["x.com"]))
        c.stage(.init(habitIDs: ["a"], domains: ["x.com", "messenger.com"], apps: [discord]), now: now, calendar: calendar)
        #expect(c.pending == nil)
        c.stage(.init(habitIDs: ["a"], domains: ["x.com"]), now: now, calendar: calendar)
        #expect(c.active?.domains.contains("messenger.com") == true)
        #expect(c.active?.apps == [discord])
        #expect(c.pending?.policy.apps == [])
    }
    @Test func readdingCancelsRemovalAndPreservesPendingHabitChanges() {
        let active = Policy(habitIDs: ["a"], domains: ["x.com", "messenger.com"], apps: [discord])
        var c = Configuration(active: active)
        c.stage(.init(habitIDs: ["b"], domains: ["x.com"]), now: now, calendar: calendar)
        var desired = c.pending!.policy; desired.domains = active.domains; desired.apps = active.apps
        c.stage(desired, now: now, calendar: calendar)
        #expect(c.active == active); #expect(c.pending?.policy.habitIDs == ["b"])
        desired.habitIDs = active.habitIDs
        c.stage(desired, now: now, calendar: calendar)
        #expect(c.pending == nil)
    }
    @Test func existingPendingAdditionsMigrateButKeepHabitsAndRemovalsDeferred() {
        let desired = Policy(habitIDs: ["b"], domains: ["messenger.com"], apps: [telegram])
        let boundary = HabitDay(now: now, calendar: calendar).end
        var c = Configuration(active: .init(habitIDs: ["a"], domains: ["x.com"], apps: [discord]),
                              pending: .init(policy: desired, effectiveAt: boundary, timezone: calendar.timeZone.identifier))
        c.advance(now: now, calendar: calendar)
        #expect(c.active?.habitIDs == ["a"])
        #expect(Set(c.active?.domains ?? []) == ["x.com", "messenger.com"])
        #expect(Set(c.active?.apps.map(\.id) ?? []) == [discord.id, telegram.id])
        #expect(c.pending?.effectiveAt == boundary)
        #expect(c.pending?.policy == desired)
        let first = c
        c.advance(now: now.addingTimeInterval(5), calendar: calendar)
        #expect(c == first)
    }
    @Test func additionsOnlyMigrationAndReorderingDoNotLeavePendingRules() {
        let active = Policy(habitIDs: ["a", "b"], domains: ["x.com"])
        let desired = Policy(habitIDs: ["b", "a"], domains: ["messenger.com", "x.com"], apps: [discord])
        var c = Configuration(active: active, pending: .init(policy: desired, effectiveAt: now.addingTimeInterval(100), timezone: calendar.timeZone.identifier))
        c.advance(now: now, calendar: calendar)
        #expect(c.pending == nil)
        #expect(Set(c.active?.habitIDs ?? []) == ["a", "b"])
        #expect(c.active?.apps == [discord])
    }
    @Test func restartKeepsImmediateCoverageAndDeferredRemoval() throws {
        var c = Configuration(active: .init(habitIDs: ["a"], domains: ["x.com"], apps: [discord]))
        c.stage(.init(habitIDs: ["b"], domains: ["messenger.com"], apps: [telegram]), now: now, calendar: calendar)
        var loaded = try GateFiles.decoder().decode(Configuration.self, from: GateFiles.encoder().encode(c))
        #expect(loaded == c)
        loaded.advance(now: HabitDay(now: now, calendar: calendar).end, calendar: calendar)
        #expect(loaded.active?.domains == ["messenger.com"])
        #expect(loaded.active?.apps == [telegram])
        #expect(loaded.active?.habitIDs == ["b"])
    }
    @Test func timezoneRebaseDoesNotRemoveExistingTargetsEarly() {
        var c = Configuration(active: .init(habitIDs: ["a"], domains: ["x.com"], apps: [discord]))
        c.stage(.init(habitIDs: ["b"], domains: ["messenger.com"], apps: [telegram]), now: now, calendar: calendar)
        var shifted = calendar; shifted.timeZone = TimeZone(identifier: "America/New_York")!
        c.advance(now: now, calendar: shifted)
        #expect(c.active?.habitIDs == ["a"])
        #expect(c.active?.domains.contains("x.com") == true)
        #expect(c.active?.apps.contains(discord) == true)
        #expect(c.pending?.effectiveAt == HabitDay(now: now, calendar: shifted).end)
    }
}
