import Foundation
import GateCore
import Testing
@testable import HabitGate

private struct PrivateCredentialError: LocalizedError {
    var errorDescription: String? { "private credential service details" }
}

private actor DeferredCredentialStorage: CredentialStorage {
    private var pending: CheckedContinuation<String?, Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var loadCalls = 0
    private(set) var saved: [String] = []
    func load() async throws -> String? {
        loadCalls += 1
        waiter?.resume(); waiter = nil
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func save(_ key: String) { saved.append(key) }
    func delete() { saved.removeAll() }
    func waitForLoad() async {
        if loadCalls > 0 { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish(_ result: Result<String?, Error>) { pending?.resume(with: result); pending = nil }
}

private actor ImmediateCredentialStorage: CredentialStorage {
    var value: String?
    var fails = false
    init(_ value: String?, fails: Bool = false) { self.value = value; self.fails = fails }
    func load() throws -> String? {
        if fails { throw PrivateCredentialError() }
        return value
    }
    func save(_ key: String) throws {
        if fails { throw PrivateCredentialError() }
        value = key
    }
    func delete() throws { if fails { throw PrivateCredentialError() }; value = nil }
    func setFailure(_ value: Bool) { fails = value }
}

@Suite(.serialized) @MainActor struct CredentialTests {
    @Test func pendingAuthorizationDoesNotPreventAppGuardWork() async {
        let storage = DeferredCredentialStorage()
        let credentials = CredentialSession(storage: storage)
        let restore = Task { await credentials.load() }
        await storage.waitForLoad()
        #expect(credentials.state == .loading)
        #expect(credentials.key == nil)

        // This must run on the UI actor even while the credential read is pending.
        let discord = FakeGuardedApp("com.hnc.Discord", active: true)
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        var explained = false
        blocker.onBlocked = { _ in explained = true }
        blocker.update(apps: [.init(bundleID: "com.hnc.Discord", name: "Discord")], snapshot: .locked())
        #expect(discord.isHidden)
        #expect(explained)
        #expect(credentials.state == .loading)

        await storage.finish(.success("fixture-saved-value"))
        await restore.value
        #expect(credentials.state == .ready)
    }

    @Test func repeatedRestoreDoesNotQueueAnotherAuthorizationPrompt() async {
        let storage = DeferredCredentialStorage()
        let credentials = CredentialSession(storage: storage)
        let first = Task { await credentials.load() }
        await storage.waitForLoad()
        await credentials.load()
        #expect(await storage.loadCalls == 1)
        await storage.finish(.success(nil))
        await first.value
        #expect(credentials.state == .missing)
    }

    @Test func cachedUnlockStillExpiresWhileAuthorizationIsPending() async {
        let storage = DeferredCredentialStorage()
        let credentials = CredentialSession(storage: storage)
        let restore = Task { await credentials.load() }
        await storage.waitForLoad()
        let now = Date()
        var proof = GateSnapshot.locked(now: now)
        proof.access = "allowed"; proof.lastSyncedAt = now
        let discord = FakeGuardedApp("com.hnc.Discord", active: true)
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        let apps = [BlockedApp(bundleID: "com.hnc.Discord", name: "Discord")]
        blocker.update(apps: apps, snapshot: proof, now: now)
        #expect(!discord.isHidden)
        blocker.update(apps: apps, snapshot: proof, now: proof.expiresAt)
        #expect(discord.isHidden)
        #expect(credentials.state == .loading)
        await storage.finish(.success(nil))
        await restore.value
    }

    @Test func aLateReadCannotReplaceAReconnectedCredential() async throws {
        let storage = DeferredCredentialStorage()
        let credentials = CredentialSession(storage: storage)
        let restore = Task { await credentials.load() }
        await storage.waitForLoad()
        try await credentials.save("fixture-replacement-value")
        await storage.finish(.success("fixture-obsolete-value"))
        await restore.value
        #expect(credentials.key == "fixture-replacement-value")
        #expect(credentials.state == .ready)
        #expect(await storage.saved == ["fixture-replacement-value"])
    }

    @Test func deniedAccessIsDistinctFromAnAbsentKeyAndCanBeRetried() async {
        let storage = ImmediateCredentialStorage(nil, fails: true)
        let credentials = CredentialSession(storage: storage)
        await credentials.load()
        guard case .unavailable(let notice) = credentials.state else {
            Issue.record("Expected a Keychain access problem"); return
        }
        #expect(notice.contains("Keychain"))
        #expect(!notice.contains("private credential service details"))
        #expect(credentials.key == nil)
        await storage.setFailure(false)
        await credentials.load()
        #expect(credentials.state == .missing)
    }

    @Test func failedReplacementPreservesTheUsableInMemoryKey() async {
        let storage = ImmediateCredentialStorage("fixture-existing-value")
        let credentials = CredentialSession(storage: storage)
        await credentials.load()
        await storage.setFailure(true)
        do { try await credentials.save("fixture-unsaved-value"); Issue.record("Expected a save failure") } catch { }
        #expect(credentials.key == "fixture-existing-value")
        #expect(credentials.state == .ready)
    }
    @Test func disconnectInvalidatesAnOutstandingCredentialRead() async {
        let storage = DeferredCredentialStorage(); let credentials = CredentialSession(storage: storage)
        let read = Task { await credentials.load() }; await storage.waitForLoad()
        await credentials.disconnect(deleteKey: false)
        await storage.finish(.success("fixture-old-value")); await read.value
        #expect(credentials.key == nil); #expect(credentials.state == .disconnected)
    }
    @Test func deletionRemovesOnlyCredentialAndFailureStaysDisconnected() async throws {
        let storage = ImmediateCredentialStorage("fixture-value"); let credentials = CredentialSession(storage: storage)
        await credentials.load(); await credentials.disconnect(deleteKey: true)
        #expect(try await storage.load() == nil); #expect(credentials.key == nil)
        try await credentials.save("fixture-new-value"); await storage.setFailure(true)
        await credentials.disconnect(deleteKey: true)
        #expect(credentials.key == nil)
        if case .unavailable(let message) = credentials.state { #expect(message.contains("could not be deleted")) }
        else { Issue.record("Deletion failure must be visible") }
    }

}
