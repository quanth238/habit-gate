import Foundation
import Testing
import GateCore
@testable import HabitGate
private actor EmptyVault: CredentialStorage {
    func load() -> String? { nil }
    func save(_ key: String) {}
    func delete() {}
}
@MainActor struct StoreRecoveryTests {
    @Test func runtimeCorruptionLocksWithoutDiscardingKnownSelections() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("habit-gate-store-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = Policy(habitIDs: ["fixture"], domains: ["x.com"])
        let config = Configuration(active: policy)
        try ConfigurationRepository.save(config, root: root)
        let proof = PolicyEngine.evaluate(policy: policy, habits: [.init(id: "fixture", name: "Fixture")], journal: [.init(id: "fixture", status: "completed")], now: Date())
        try GateFiles.write(proof, "snapshot.json", root: root)
        let store = GateStore(root: root, vault: EmptyVault())
        #expect(store.snapshot.access == "allowed")
        try Data("{damaged".utf8).write(to: root.appendingPathComponent("configuration.json"))
        store.tick()
        #expect(store.needsRecovery); #expect(!store.storageIssue.isEmpty)
        #expect(store.snapshot.access == "blocked"); #expect(store.configuration == config)
        store.setNotifications(true)
        #expect(store.configuration == config)
        #expect(String(data: try Data(contentsOf: root.appendingPathComponent("configuration.json")), encoding: .utf8) == "{damaged")
    }
    @Test func allowanceNeverChangesHabitsWebsitesOrPermanentAppRules() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("habit-gate-allowance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = Policy(habitIDs: ["fixture"], domains: ["x.com"], apps: [.init(bundleID: "com.example.chat", name: "Chat")])
        let config = Configuration(active: policy)
        try ConfigurationRepository.save(config, root: root)
        let store = GateStore(root: root, vault: EmptyVault())
        store.tick()
        let proof = store.snapshot
        #expect(store.startDailyAccess())
        store.refreshDailyAccess()
        #expect(store.temporaryAccess.isCounting)
        #expect(store.configuration == config); #expect(store.snapshot == proof)
        #expect(store.snapshot.access == "blocked")
        #expect(store.temporaryAccess.grant()?.allows("com.example.chat", at: Date()) == true)
        store.snapshot.access = "allowed"; store.snapshot.lastSyncedAt = Date()
        store.refreshDailyAccess()
        #expect(!store.temporaryAccess.isCounting); #expect(store.temporaryAccess.grant() == nil)
    }

    @Test func weekendSettingPersistsWithoutChangingSelectionsOrTheDailyLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("habit-gate-weekend-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = Policy(habitIDs: ["fixture"], domains: ["x.com"], apps: [.init(bundleID: "com.example.chat", name: "Chat")])
        try ConfigurationRepository.save(Configuration(active: policy), root: root)
        let store = GateStore(root: root, vault: EmptyVault())
        let budget = store.temporaryAccess.budget
        store.setWeekendsOff(true)
        #expect(store.configuration.weekendsOff == true)
        #expect(store.configuration.active == policy)
        #expect(ConfigurationRepository.load(root: root).configuration.weekendsOff == true)
        #expect(store.temporaryAccess.budget.usedSeconds == budget.usedSeconds)
        #expect(store.temporaryAccess.budget.todayMinutes == budget.todayMinutes)
        store.setWeekendsOff(false)
        #expect(store.configuration.weekendsOff != true)
        #expect(store.configuration.active == policy)
        #expect(!store.snapshot.isWeekendDayOff)
    }

    @Test func weekendSettingCannotBypassCorruptConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("habit-gate-weekend-recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var config = Configuration(active: Policy(habitIDs: ["fixture"]))
        config.weekendsOff = true
        try ConfigurationRepository.save(config, root: root)
        try Data("bad json".utf8).write(to: root.appendingPathComponent("configuration.json"))
        let store = GateStore(root: root, vault: EmptyVault())
        store.tick()
        #expect(store.needsRecovery); #expect(!store.normalAccess)
        #expect(store.snapshot.access == "blocked")
    }

}
