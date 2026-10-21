import Foundation
import Testing
@testable import GateCore

struct DailyAccessTests {
    let now = Date(timeIntervalSince1970: 1_792_500_000)
    @Test func grantIsScopedToConfiguredMacAppsAndExpiresExactly() {
        let apps = [BlockedApp(bundleID: "com.example.Chat", name: "Chat"), .init(bundleID: "com.example.Other", name: "Other")]
        let proof = GateSnapshot.locked(now: now)
        let grant = AppAccessGrant(bundleIDs: [apps[0].id], expiresAt: now.addingTimeInterval(60))
        #expect(!AppRules.shouldBlock(bundleID: apps[0].bundleID, apps: apps, snapshot: proof, now: now, allowance: grant))
        #expect(AppRules.shouldBlock(bundleID: apps[1].bundleID, apps: apps, snapshot: proof, now: now, allowance: grant))
        #expect(AppRules.shouldBlock(bundleID: apps[0].bundleID, apps: apps, snapshot: proof, now: grant.expiresAt, allowance: grant))
        #expect(proof.access == "blocked")
    }
    @Test func strictDurationValidation() {
        for value in ["", "0", "121", "-1", "1.5", "1e2", " 15", "١٥", "999999999999999999999"] {
            #expect(DailyAccessBudget.minutes(value) == nil)
        }
        for value in [1, 5, 15, 30, 60, 120] { #expect(DailyAccessBudget.minutes(String(value)) == value) }
    }
    @Test func oneSharedBalanceHasNoNegativeOrExtraTime() {
        var budget = DailyAccessBudget(now: now)
        #expect(budget.todayMinutes == 15); #expect(budget.remainingSeconds == 900)
        budget.consume(400); budget.consume(500)
        #expect(budget.remainingSeconds == 0)
        budget.consume(500); #expect(budget.usedSeconds == 900)
        budget.consume(-30); #expect(budget.remainingSeconds == 0)
    }
    @Test func privateAtomicStorageRejectsMalformedAndPubliclyReadableData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(DailyAccessFile.load(root: root) == nil)
        let budget = DailyAccessBudget(now: now); try DailyAccessFile.save(budget, root: root)
        #expect(DailyAccessFile.load(root: root) == budget)
        let url = root.appendingPathComponent(DailyAccessFile.name)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(DailyAccessFile.load(root: root) == nil)
        try Data("{broken".utf8).write(to: url)
        #expect(DailyAccessFile.load(root: root) == nil)
    }
    @Test func invalidRecordsAreRejected() {
        var value = DailyAccessBudget(now: now)
        value.usedSeconds = -1; #expect(!value.wellFormed)
        value.usedSeconds = 901; #expect(!value.wellFormed)
        value.usedSeconds = 0; value.limitMinutes = 121; #expect(!value.wellFormed)
        value.limitMinutes = 15; value.activeSince = now.addingTimeInterval(1); #expect(!value.wellFormed)
        value.activeSince = nil; value.activeBundleID = "com.example.chat"; #expect(!value.wellFormed)
    }
    @Test func countdownAndLegacyForegroundRecordsRemainReadable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var value = DailyAccessBudget(now: now)
        value.activeSince = now
        try DailyAccessFile.save(value, root: root)
        #expect(DailyAccessFile.load(root: root) == value)
        value.activeBundleID = "com.example.chat"
        try DailyAccessFile.save(value, root: root)
        #expect(DailyAccessFile.load(root: root) == value)
    }
}
