import Foundation

public struct ConfigurationLoad {
    public var configuration: Configuration
    public var needsRecovery: Bool
    public var issue: String?
}

// Keep recovery explicit. A malformed file is never interpreted as a new install.
public enum ConfigurationRepository {
    public static func validate(_ value: Configuration) throws {
        for policy in [value.active, value.pending?.policy, value.draft].compactMap({ $0 }) {
            let normalized = try DomainRules.validated(policy.domains)
            guard Set(normalized) == Set(policy.domains) else { throw GateError.invalid("Website rules need normalized domains.") }
            _ = try AppRules.validated(policy.apps)
            guard Set(policy.habitIDs).count == policy.habitIDs.count else { throw GateError.invalid("Duplicate essential habits.") }
        }
        if let active = value.active, active.habitIDs.isEmpty { throw GateError.invalid("Active essentials are missing.") }
        if let pending = value.pending, pending.policy.habitIDs.isEmpty { throw GateError.invalid("Pending essentials are missing.") }
        if value.pending != nil && value.active == nil { throw GateError.invalid("Active rules are missing.") }
    }
    private static func valid(_ name: String, root: URL) -> Configuration? {
        guard let value = GateFiles.read(Configuration.self, name, root: root), (try? validate(value)) != nil else { return nil }
        return value
    }
    public static func load(root: URL = GateFiles.root) -> ConfigurationLoad {
        if let value = valid("configuration.json", root: root) {
            return .init(configuration: value, needsRecovery: false, issue: nil)
        }
        if let backup = valid("configuration.last-good.json", root: root) {
            return .init(configuration: backup, needsRecovery: true,
                         issue: "Saved rules could not be read. Access stays locked using the recovery copy. Restore saved rules to continue.")
        }
        let cached = GateFiles.read(GateSnapshot.self, "snapshot.json", root: root)
        let hasFile = FileManager.default.fileExists(atPath: root.appendingPathComponent("configuration.json").path)
        if !hasFile && (cached?.habits.isEmpty ?? true) && (cached?.guardedApps?.isEmpty ?? true) {
            return .init(configuration: .init(), needsRecovery: false, issue: nil)
        }
        var recovered = Configuration()
        if let cached, !cached.habits.isEmpty {
            recovered.active = .init(habitIDs: Array(Set(cached.habits.map(\.id))).sorted(),
                                     domains: (try? DomainRules.validated(cached.domains)) ?? DomainRules.defaults,
                                     apps: (try? AppRules.validated(cached.guardedApps ?? [])) ?? [])
        }
        return .init(configuration: recovered, needsRecovery: true,
                     issue: "Saved rules and their recovery copy are unavailable. Access stays locked. Review the recovered selections before restoring; some targets may need to be selected again.")
    }
    // A committed primary write determines success. A failed recovery-copy write
    // is surfaced separately, without pretending the primary commit was rolled back.
    @discardableResult public static func save(_ value: Configuration, root: URL = GateFiles.root,
        write: (Configuration, String, URL) throws -> Void = { try GateFiles.write($0, $1, root: $2) }) throws -> Bool {
        try validate(value)
        try write(value, "configuration.json", root)
        do { try write(value, "configuration.last-good.json", root); return true }
        catch { return false }
    }
    public static func snapshot(for loaded: ConfigurationLoad, cached: GateSnapshot?, now: Date = Date(), calendar: Calendar = .current) -> GateSnapshot {
        var config = loaded.configuration
        config.advance(now: now, calendar: calendar)
        let policy = config.active
        let domains = policy?.domains ?? config.draft?.domains ?? cached?.domains ?? DomainRules.defaults
        var result = cached?.sanitized(at: now, calendar: calendar) ?? .locked(now: now, calendar: calendar, domains: domains)
        if loaded.needsRecovery || config.disconnected == true || policy == nil || Set(result.habits.map(\.id)) != Set(policy?.habitIDs ?? []) ||
            (result.access == "allowed" && result.remainingCount > 0) {
            result = .locked(now: now, calendar: calendar, domains: domains,
                             reason: loaded.needsRecovery ? "Saved rules need recovery. Access stays locked." :
                             config.disconnected == true ? "Habitify is disconnected. Reconnect to verify your essentials." :
                             policy == nil ? "Finish setup and review your rules before activating protection." : "Current essentials need verification.")
        }
        result.domains = domains
        result.guardedApps = policy?.apps ?? []
        return result
    }
}

public extension Configuration {
    func canActivateDraft(keyVerified: Bool, clients: [BrowserClient], now: Date = Date()) -> Bool {
        guard active == nil, let draft, keyVerified, !draft.habitIDs.isEmpty else { return false }
        return clients.contains {
            now.timeIntervalSince($0.seenAt) >= -5 && now.timeIntervalSince($0.seenAt) < 150 &&
            $0.permissionsOK && $0.rulesOK == true && Set($0.checkedDomains ?? []) == Set(draft.domains)
        }
    }
}
