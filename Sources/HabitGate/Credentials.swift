import Foundation

protocol CredentialStorage: Sendable {
    func load() async throws -> String?
    func save(_ key: String) async throws
    func delete() async throws
}

// Blocking Security.framework calls run on this actor, never on the UI actor.
// A macOS authorization prompt can wait here while the app guard keeps working.
actor KeychainVault: CredentialStorage {
    func load() throws -> String? { try KeychainStore.load() }
    func save(_ key: String) throws { try KeychainStore.save(key) }
    func delete() throws { try KeychainStore.delete() }
}

enum CredentialState: Equatable {
    case idle, loading, ready, missing, disconnected
    case unavailable(String)

    var notice: String? {
        switch self {
        case .idle, .loading:
            return "Waiting for macOS Keychain. Approve Habit Gate’s request on your Mac if prompted. Existing blocking rules remain active."
        case .unavailable(let message): return message
        case .missing: return "No saved Habitify key was found. Connect Habitify in Settings. Existing blocking rules remain active."
        case .disconnected: return "Habitify is disconnected. Reconnect to verify completion. Your saved blocking rules remain active."
        case .ready: return nil
        }
    }
}

@MainActor final class CredentialSession {
    private let storage: any CredentialStorage
    private var revision = 0
    private var readInFlight = false
    private(set) var key: String?
    private(set) var state: CredentialState = .idle

    init(storage: any CredentialStorage) { self.storage = storage }

    func load() async {
        guard !readInFlight else { return }
        readInFlight = true
        revision += 1
        let request = revision
        state = .loading
        defer { readInFlight = false }
        do {
            let saved = try await storage.load()
            // A reconnect may have saved a replacement while this read was waiting.
            guard request == revision else { return }
            key = saved
            state = saved == nil ? .missing : .ready
        } catch {
            guard request == revision else { return }
            state = .unavailable("macOS Keychain access is unavailable. Retry in Connection settings and approve the system request on your Mac. Existing blocking rules remain active.")
        }
    }

    func save(_ value: String) async throws {
        revision += 1
        let request = revision
        do {
            try await storage.save(value)
            guard request == revision else { return }
            key = value
            state = .ready
        } catch {
            if request == revision {
                state = key == nil ? .unavailable("Could not save the Habitify key in macOS Keychain. Retry the connection on this Mac.") : .ready
            }
            throw error
        }
    }
    func disconnect(deleteKey: Bool) async {
        revision += 1
        key = nil; state = .disconnected
        if deleteKey {
            do { try await storage.delete() }
            catch { state = .unavailable("Disconnected, but the saved API key could not be deleted. Retry Delete API key in Connection settings.") }
        }
    }
}
