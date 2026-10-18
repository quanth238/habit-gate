import Foundation
import Testing
@testable import GateCore

struct RecoveryTests {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!; return c }
    var now: Date { ISO8601DateFormatter().date(from: "2026-10-18T07:00:00Z")! }
    func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("habit-gate-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    var policy: Policy { .init(habitIDs: ["a"], domains: ["x.com"], apps: [.init(bundleID: "com.hnc.Discord", name: "Discord")]) }
    func proof() -> GateSnapshot {
        PolicyEngine.evaluate(policy: policy, habits: [.init(id: "a", name: "Read")], journal: [.init(id: "a", status: "completed")], now: now, calendar: calendar)
    }
    @Test func corruptPrimaryUsesRecoveryWithoutOverwritingEvidence() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let config = Configuration(active: policy)
        try ConfigurationRepository.save(config, root: root)
        let damaged = Data("{damaged".utf8); try damaged.write(to: root.appendingPathComponent("configuration.json"))
        let loaded = ConfigurationRepository.load(root: root)
        #expect(loaded.needsRecovery); #expect(loaded.configuration == config)
        #expect(try Data(contentsOf: root.appendingPathComponent("configuration.json")) == damaged)
        let state = ConfigurationRepository.snapshot(for: loaded, cached: proof(), now: now, calendar: calendar)
        #expect(state.access == "blocked"); #expect(state.guardedApps == policy.apps)
    }
    @Test func missingPrimaryWithBackupIsNotANewInstallation() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        try GateFiles.write(Configuration(active: policy), "configuration.last-good.json", root: root)
        #expect(ConfigurationRepository.load(root: root).needsRecovery)
        #expect(ConfigurationRepository.load(root: root).configuration.active == policy)
    }
    @Test func failedPrimarySavePreservesCommittedPolicy() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let original = Configuration(active: policy); try ConfigurationRepository.save(original, root: root)
        var changed = original; changed.active?.domains.append("messenger.com")
        do {
            try ConfigurationRepository.save(changed, root: root, write: { _, _, _ in throw GateError.invalid("fixture denied write") })
            Issue.record("Expected write failure")
        } catch { }
        #expect(ConfigurationRepository.load(root: root).configuration == original)
    }
    @Test func backupFailureDoesNotPretendPrimaryCommitRolledBack() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let committed = Configuration(active: policy)
        let copied = try ConfigurationRepository.save(committed, root: root) { value, name, directory in
            if name.contains("last-good") { throw GateError.invalid("fixture disk full") }
            try GateFiles.write(value, name, root: directory)
        }
        #expect(!copied); #expect(ConfigurationRepository.load(root: root).configuration == committed)
    }
    @Test func staleProofCannotUnlockChangedEssentialsAfterFailedSnapshotSave() {
        let changed = Configuration(active: .init(habitIDs: ["a", "b"], domains: ["messenger.com"]))
        let state = ConfigurationRepository.snapshot(for: .init(configuration: changed, needsRecovery: false), cached: proof(), now: now, calendar: calendar)
        #expect(state.access == "blocked"); #expect(state.domains == ["messenger.com"])
    }
    @Test func addedTargetsUseSameValidHabitProofEvenIfSnapshotLags() {
        var config = Configuration(active: policy); config.active?.domains.append("messenger.com")
        let state = ConfigurationRepository.snapshot(for: .init(configuration: config, needsRecovery: false), cached: proof(), now: now, calendar: calendar)
        #expect(state.access == "allowed"); #expect(state.domains.contains("messenger.com"))
    }
    @Test func pendingBoundaryIsAppliedByReaderBeforeAcceptingCachedProof() {
        var config = Configuration(active: policy)
        config.stage(.init(habitIDs: ["b"], domains: ["messenger.com"]), now: now, calendar: calendar)
        let state = ConfigurationRepository.snapshot(for: .init(configuration: config, needsRecovery: false), cached: proof(), now: HabitDay(now: now, calendar: calendar).end, calendar: calendar)
        #expect(state.access == "blocked"); #expect(state.domains == ["messenger.com"])
    }
    @Test func disconnectedStateRetainsTargetsAndCannotReuseUnlock() {
        var config = Configuration(active: policy); config.disconnected = true
        let state = ConfigurationRepository.snapshot(for: .init(configuration: config, needsRecovery: false), cached: proof(), now: now, calendar: calendar)
        #expect(state.access == "blocked"); #expect(state.guardedApps == policy.apps)
    }
    @Test func setupDraftSurvivesRestartWithoutActivating() throws {
        var config = Configuration(); config.draft = policy
        let loaded = try GateFiles.decoder().decode(Configuration.self, from: GateFiles.encoder().encode(config))
        #expect(loaded.active == nil); #expect(loaded.draft == policy)
        let state = ConfigurationRepository.snapshot(for: .init(configuration: loaded, needsRecovery: false), cached: nil, now: now, calendar: calendar)
        #expect(state.domains == policy.domains); #expect(state.access == "blocked")
    }
    @Test func nonGregorianSystemCalendarUsesGregorianHabitifyDate() throws {
        var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = calendar.timeZone
        #expect(HabitDay(now: now, calendar: buddhist).date == "2026-10-18")
        #expect(try PolicyEngine.due(.init(id: "a", name: "Read"), on: "2026-10-18", calendar: buddhist))
        #expect(proof().valid(at: now, calendar: buddhist))
        var alias = calendar; alias.timeZone = TimeZone(identifier: "Asia/Saigon")!
        #expect(proof().valid(at: now, calendar: alias))
    }
    @Test func activationNeedsFreshCoverageForTheExactDraftAndCannotRepeat() {
        var config = Configuration(); config.draft = policy
        var client = BrowserClient(id: "fixture-profile", seenAt: now, privateAccess: false, permissionsOK: true)
        #expect(!config.canActivateDraft(keyVerified: true, clients: [client], now: now))
        client.rulesOK = true; client.checkedDomains = ["instagram.com"]
        #expect(!config.canActivateDraft(keyVerified: true, clients: [client], now: now))
        client.checkedDomains = policy.domains
        #expect(config.canActivateDraft(keyVerified: true, clients: [client], now: now))
        #expect(!config.canActivateDraft(keyVerified: false, clients: [client], now: now))
        #expect(!config.canActivateDraft(keyVerified: true, clients: [client], now: now.addingTimeInterval(150)))
        config.active = policy
        #expect(!config.canActivateDraft(keyVerified: true, clients: [client], now: now))
    }

}
