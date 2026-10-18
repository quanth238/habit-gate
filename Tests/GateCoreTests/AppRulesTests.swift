import Testing
import Foundation
@testable import GateCore

struct AppRulesTests {
    let discord = BlockedApp(bundleID: "com.hnc.Discord", name: "Discord")
    @Test func existingPoliciesMigrateAndNewSelectionsRoundtrip() throws {
        let old = Data(#"{"active":{"habitIDs":["a"],"domains":["x.com"]},"notifyOnUnlock":false}"#.utf8)
        var config = try GateFiles.decoder().decode(Configuration.self, from: old)
        #expect(config.active?.apps == [])
        config.active?.apps = [discord]
        let decoded = try GateFiles.decoder().decode(Configuration.self, from: GateFiles.encoder().encode(config))
        #expect(decoded == config)
    }
    @Test func appAdditionsApplyNowAndRemovalsWaitForFourAM() {
        let now = Date()
        let current = Policy(habitIDs: ["a", "b"], domains: ["x.com"])
        var next = current; next.apps = [discord]
        var config = Configuration(active: current)
        config.stage(next, now: now)
        #expect(config.active == next); #expect(config.pending == nil)
        config.advance(now: HabitDay(now: now).end)
        #expect(config.active == next)
        var remove = next; remove.apps = []
        config.stage(remove, now: HabitDay(now: now).end)
        #expect(config.active?.apps == [discord])
    }
    @Test func exactApplicationIdentityAndProtectedApps() throws {
        #expect(try AppRules.validated([discord]) == [discord])
        let snapshot = GateSnapshot.locked()
        #expect(AppRules.shouldBlock(bundleID: discord.bundleID, apps: [discord], snapshot: snapshot))
        #expect(!AppRules.shouldBlock(bundleID: discord.bundleID + ".other", apps: [discord], snapshot: snapshot))
        #expect(!AppRules.shouldBlock(bundleID: nil, apps: [discord], snapshot: snapshot))
        for id in ["co.vuvo.habitify", "me.habitgate.app", "com.apple.finder", "com.apple.systempreferences", "bad/id"] {
            #expect(!AppRules.selectable(id))
            #expect(throws: (any Error).self) { try AppRules.validated([.init(bundleID: id, name: "Protected")]) }
        }
        #expect(throws: (any Error).self) { try AppRules.validated([discord, discord]) }
    }
}
