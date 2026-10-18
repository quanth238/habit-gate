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
}
