import Foundation
import AppKit
import SwiftUI
import Network
import ServiceManagement
import UserNotifications
import GateCore
import UniformTypeIdentifiers

@MainActor final class GateStore: ObservableObject {
    @Published var configuration: Configuration
    @Published var snapshot: GateSnapshot
    @Published var catalog: [Habit] = []
    @Published var isSyncing = false
    @Published var message = ""
    @Published var clients: [BrowserClient] = []
    @Published private(set) var hasKey = false
    @Published private(set) var credentialState: CredentialState = .idle
    @Published var blockedApp: BlockedApp?
    @Published var appProtectionIssue = ""
    @Published var storageIssue = ""
    @Published var guardedAppIDs = Set<String>()
    @Published private(set) var needsRecovery = false
    let temporaryAccess: DailyAccessController
    @Published var temporaryAccessRequest: UUID?
    var temporaryAccessOpensSettings = false
    var pendingAccessApp: BlockedApp?
    var dismissBlockedApp: (() -> Void)?
    let root: URL
    var showToday: (() -> Void)?
    var showSettings: (() -> Void)?
    var toggleFullScreen: (() -> Void)?
    var statusChanged: (() -> Void)?
    var showBlockedApp: (() -> Void)?
    private let appBlocker = AppBlocker()
    private let credentials: CredentialSession
    private var key: String? { credentials.key }
    var isLoadingCredentials: Bool { credentialState == .loading || credentialState == .idle }
    var credentialNotice: String? { credentialState.notice }
    private var timer: Timer?
    private var monitor = NWPathMonitor()
    private var lastAttempt = Date.distantPast
    private var retryAt = Date.distantPast
    private var failures = 0
    private var lastPersisted: GateSnapshot?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshObserver: NSObjectProtocol?
    init(root: URL = GateFiles.root, vault: any CredentialStorage = KeychainVault()) {
        self.root = root
        temporaryAccess = DailyAccessController(root: root)
        credentials = CredentialSession(storage: vault)
        let loaded = ConfigurationRepository.load(root: root)
        configuration = loaded.configuration
        needsRecovery = loaded.needsRecovery; storageIssue = loaded.issue ?? ""
        snapshot = ConfigurationRepository.snapshot(for: loaded, cached: GateFiles.read(GateSnapshot.self, "snapshot.json", root: root))
        if !snapshot.isWeekendDayOff { snapshot.syncState = nil }
        catalog = GateFiles.read([Habit].self, "catalog.json", root: root) ?? []
        if !needsRecovery, FileManager.default.fileExists(atPath: root.appendingPathComponent("configuration.json").path),
           !FileManager.default.fileExists(atPath: root.appendingPathComponent("configuration.last-good.json").path) {
            do { try GateFiles.write(configuration, "configuration.last-good.json", root: root) }
            catch { storageIssue = "Could not create a recovery copy. Check local storage before changing rules." }
        }
        if configuration.disconnected == true { credentialState = .disconnected }
    }
    func start() {
        temporaryAccess.onChange = { [weak self] in
            guard let self else { return }
            self.appBlocker.update(apps: self.configuration.active?.apps ?? [], snapshot: self.snapshot, allowance: self.temporaryAccess.grant())
            self.objectWillChange.send(); self.statusChanged?()
        }
        appBlocker.onForeground = { [weak self] _ in self?.refreshDailyAccess() }
        appBlocker.onBlocked = { [weak self] app in
            self?.blockedApp = app; self?.showBlockedApp?()
        }
        appBlocker.onIssue = { [weak self] text in
            if self?.appProtectionIssue != text { self?.appProtectionIssue = text }
        }
        appBlocker.onVerified = { [weak self] ids in
            if self?.guardedAppIDs != ids { self?.guardedAppIDs = ids }
        }
        appBlocker.start()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 1
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.tick(forceSync: true)
                }
            })
        }
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSSystemClockDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.tick(forceSync: true) }
            })
        }
        refreshObserver = DistributedNotificationCenter.default().addObserver(forName: .init(GateFiles.refreshNotification), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick(forceSync: true) }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.tick(forceSync: true) }
        }
        monitor.start(queue: DispatchQueue(label: "me.habitgate.network"))
        Task { await restoreCredentials() }
    }
    func restoreCredentials() async {
        guard credentialState != .loading, configuration.disconnected != true else { return }
        credentialState = .loading
        await credentials.load()
        credentialState = credentials.state
        hasKey = credentials.key != nil
        if hasKey { tick(forceSync: true) }
    }
    func tick(forceSync: Bool = false) {
        let now = Date()
        if !needsRecovery {
            let disk = ConfigurationRepository.load(root: root)
            if disk.needsRecovery || disk.configuration != configuration {
                needsRecovery = true
                storageIssue = "Saved rules changed or became unreadable. Access stays locked using the rules already known by this app. Review and restore them before continuing."
            }
        }
        if needsRecovery {
            snapshot.access = "blocked"; persistSnapshot(); return
        }
        var updated = configuration; updated.advance(now: now)
        if updated != configuration {
            do {
                let habitsChanged = updated.active?.habitIDs != configuration.active?.habitIDs
                try commitConfiguration(updated); configuration = updated
                if habitsChanged {
                    snapshot = .locked(domains: updated.active?.domains ?? DomainRules.defaults, reason: "New daily rules are active. Checking Habitify.")
                    lastAttempt = .distantPast; retryAt = .distantPast
                } else if let policy = updated.active { snapshot.domains = policy.domains }
            } catch { snapshot.access = "blocked"; persistSnapshot(); return }
        }
        if refreshWeekendSchedule(now: now) {
            if message != snapshot.reason { message = snapshot.reason }
        } else if snapshot.verificationSource == WeekendSchedule.source || (!snapshot.valid(at: now) && (snapshot.access == "allowed" || snapshot.habitDate != HabitDay(now: now).date || snapshot.utcOffsetMinutes != TimeZone.current.secondsFromGMT(for: now) / 60)) {
            snapshot = .locked(domains: configuration.active?.domains ?? DomainRules.defaults, reason: "A new habit day needs verification.")
            message = snapshot.reason
            lastAttempt = .distantPast; retryAt = .distantPast
        }
        let latestClients = GateFiles.browserClients()
        // Heartbeat timestamps determine liveness in GateFiles; the UI only needs
        // profile identity and coverage changes, rather than every heartbeat.
        if !sameBrowserCoverage(clients, latestClients) { clients = latestClients }
        persistSnapshot()
        if forceSync && now < retryAt && !snapshot.isWeekendDayOff { message = "Unable to sync yet. Retry after \(retryAt.formatted(date: .omitted, time: .shortened)). Using only previously verified state." }
        let due = forceSync || now.timeIntervalSince(lastAttempt) >= 60
        if due && now >= retryAt && now.timeIntervalSince(lastAttempt) >= 3 && key != nil {
            Task { await self.sync() }
        }
    }
    func connect(_ candidate: String) async -> Bool {
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\n"), !value.contains("\r") else { message = "Enter a valid API key locally."; return false }
        guard !isSyncing else { return false }
        isSyncing = true; defer { isSyncing = false }
        do {
            let client = HabitifyClient(key: value)
            let habits = try await client.habits()
            _ = try await client.journal(date: HabitDay(now: Date()).date)
            credentialState = .loading
            try await credentials.save(value)
            credentialState = credentials.state; hasKey = true
            var connected = configuration; connected.disconnected = nil
            try commitConfiguration(connected); configuration = connected
            try updateCatalog(habits)
            retryAt = .distantPast; failures = 0; lastAttempt = .distantPast
            message = "Connected. Choose your essential habits and websites."
            if configuration.active != nil { isSyncing = false; await sync() }
            return true
        } catch {
            credentialState = credentials.state
            hasKey = credentials.key != nil
            message = safeMessage(error); return false
        }
    }
    var desiredPolicy: Policy { configuration.pending?.policy ?? configuration.active ?? configuration.draft ?? .init(habitIDs: []) }
    func saveSetup(ids: Set<String>? = nil, domains: String? = nil, apps: [BlockedApp]? = nil) throws {
        guard configuration.active == nil, !needsRecovery else { throw GateError.invalid("Use the active rule settings.") }
        var draft = configuration.draft ?? .init(habitIDs: [])
        if let ids { try validateHabits(ids); draft.habitIDs = ids.sorted() }
        if let domains { draft.domains = try validatedDomains(domains) }
        if let apps { draft.apps = try AppRules.validated(apps) }
        var next = configuration; next.draft = draft
        try commitConfiguration(next); configuration = next
        snapshot = .locked(domains: draft.domains, reason: "Review your choices before activating protection.")
        persistSnapshot(); message = "Setup choices saved. Protection has not been activated."
    }
    var readyToActivate: Bool { !needsRecovery && configuration.canActivateDraft(keyVerified: hasKey, clients: clients) }
    func activateSetup() throws {
        guard configuration.active == nil, readyToActivate else { throw GateError.invalid("Verify a Chrome profile and its website permissions before activation.") }
        let draft = desiredPolicy
        try validateHabits(Set(draft.habitIDs))
        try save(draft, notice: "Protection activated.")
        showToday?()
    }
    func savePolicy(ids: Set<String>, domainText: String) throws {
        if configuration.active == nil { try saveSetup(ids: ids, domains: domainText); return }
        try validateHabits(ids)
        let domains = try validatedDomains(domainText)
        let apps = configuration.pending?.policy.apps ?? configuration.active?.apps ?? []
        try save(Policy(habitIDs: ids.sorted(), domains: domains, apps: apps),
                 notice: "Habits change at 4 AM. Website additions apply now; removals wait until 4 AM.")
    }
    func saveHabits(_ ids: Set<String>) throws {
        try validateHabits(ids)
        guard var policy = configuration.pending?.policy ?? configuration.active else {
            throw GateError.invalid("Activate protection first.")
        }
        policy.habitIDs = ids.sorted()
        try save(policy, notice: "Habit changes saved for the next 4 AM boundary. Today's essentials stay the same.")
    }
    func saveWebsites(_ domainText: String) throws {
        guard var policy = configuration.pending?.policy ?? configuration.active else {
            throw GateError.invalid("Connect Habitify and activate your essential habits first.")
        }
        policy.domains = try validatedDomains(domainText)
        try save(policy, notice: "Website additions are active now. Removals wait until 4 AM. Chrome normally updates within 30 seconds; custom sites need permission.")
    }
    func saveApps(_ apps: [BlockedApp]) throws {
        if configuration.active == nil { try saveSetup(apps: apps); return }
        guard var policy = configuration.pending?.policy ?? configuration.active else { return }
        policy.apps = try AppRules.validated(apps)
        try save(policy, notice: "App additions are active now. Removals wait until the next 4 AM boundary.")
    }
    private func validateHabits(_ ids: Set<String>) throws {
        guard hasKey else { throw GateError.invalid("Connect and verify Habitify first.") }
        guard !ids.isEmpty else { throw GateError.invalid("Choose at least one essential habit.") }
        guard ids.allSatisfy({ id in catalog.contains { $0.id == id && $0.supported } }) else {
            throw GateError.invalid("Choose supported daily habits. Remove missing or unsupported selections.")
        }
    }
    private func validatedDomains(_ text: String) throws -> [String] {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return try DomainRules.validated(parts)
    }
    private func save(_ policy: Policy, notice: String) throws {
        guard !needsRecovery else { throw GateError.invalid("Restore saved rules before editing them.") }
        let now = Date()
        let firstActivation = configuration.active == nil
        var next = configuration
        next.stage(policy, now: now)
        let habitsChanged = next.active?.habitIDs != configuration.active?.habitIDs
        next.draft = nil
        try commitConfiguration(next)
        configuration = next
        if habitsChanged {
            snapshot = .locked(now: now, domains: next.active?.domains ?? DomainRules.defaults,
                               reason: "Rules activated. Checking Habitify.")
            lastAttempt = .distantPast; retryAt = .distantPast
        } else {
            // Adding targets uses today's existing habit proof, including a valid
            // offline unlock. It must not activate tomorrow's habit selection.
            snapshot = snapshot.sanitized(at: now)
            snapshot.domains = next.active?.domains ?? DomainRules.defaults
        }
        if persistSnapshot() {
            message = firstActivation ? "Protection activated. Enable the Chrome extension for this profile." : notice
        }
        if habitsChanged { Task { await sync() } }
    }
    var normalAccess: Bool { snapshot.access == "allowed" && snapshot.valid(at: Date()) }
    func requestTemporaryAccess(for app: BlockedApp? = nil, settings: Bool = false) {
        pendingAccessApp = app
        temporaryAccessOpensSettings = settings
        temporaryAccessRequest = UUID(); showSettings?()
    }
    @discardableResult func startDailyAccess() -> Bool {
        tick()
        guard temporaryAccess.startAccess() else { return false }
        if let app = pendingAccessApp {
            pendingAccessApp = nil; dismissBlockedApp?()
            openGuardedApp(app)
        }
        return true
    }
    func refreshDailyAccess() {
        temporaryAccess.refresh(configured: Set(configuration.active?.apps.map(\.id) ?? []),
                                normalAccess: normalAccess, recovery: needsRecovery || !storageIssue.isEmpty)
        appBlocker.update(apps: configuration.active?.apps ?? [], snapshot: snapshot, allowance: temporaryAccess.grant())
    }
    func openBlockedApp() {
        if let app = blockedApp { openGuardedApp(app) }
    }
    private func openGuardedApp(_ app: BlockedApp) {
        guard !AppRules.shouldBlock(bundleID: app.bundleID, apps: configuration.active?.apps ?? [], snapshot: snapshot, allowance: temporaryAccess.grant()),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }
    func sync() async {
        if refreshWeekendSchedule() { message = snapshot.reason; persistSnapshot() }
        guard let key, !isSyncing, !needsRecovery, configuration.disconnected != true, Date() >= retryAt else { return }
        isSyncing = true; defer { isSyncing = false }
        lastAttempt = Date()
        let day = HabitDay(now: lastAttempt)
        let policy = configuration.active
        let usedKey = key
        snapshot.syncState = "checking"; persistSnapshot()
        do {
            let client = HabitifyClient(key: key)
            let habits = try await client.habits()
            let journal = try await client.journal(date: day.date)
            guard HabitDay(now: Date()).date == day.date,
                  configuration.active == policy, self.key == usedKey, configuration.disconnected != true else { lastAttempt = .distantPast; return }
            try updateCatalog(habits)
            if refreshWeekendSchedule() {
                snapshot.lastHabitifySyncedAt = Date(); snapshot.lastSyncedAt = snapshot.lastHabitifySyncedAt
                failures = 0; retryAt = .distantPast
                message = snapshot.reason; persistSnapshot(); return
            }
            let wasAllowed = snapshot.sanitized(at: Date()).access == "allowed"
            if let policy {
                snapshot = PolicyEngine.evaluate(policy: policy, habits: habits, journal: journal, now: Date())
                if !wasAllowed && snapshot.access == "allowed" && configuration.notifyOnUnlock { notify() }
            } else { snapshot = .locked(reason: "Connected. Select your essential habits to activate protection.") }
            snapshot.syncState = "verified"
            failures = 0; retryAt = .distantPast
            message = configuration.active == nil ? "Connected. Select your essential habits." : "Synced with Habitify."
            persistSnapshot()
        } catch {
            guard self.key == usedKey, configuration.disconnected != true else { return }
            failures += 1
            let base = [60.0, 120, 300, 900][min(failures - 1, 3)]
            var delay = base
            if case let APIError.response(_, requested) = error { delay = max(base, requested ?? 0) }
            retryAt = Date().addingTimeInterval(delay)
            if refreshWeekendSchedule() { message = snapshot.reason; persistSnapshot(); return }
            snapshot = snapshot.sanitized(at: Date()); snapshot.syncError = safeMessage(error); snapshot.syncState = "failed"
            message = snapshot.syncError!
            persistSnapshot()
        }
    }
    @discardableResult private func refreshWeekendSchedule(now: Date = Date()) -> Bool {
        guard !needsRecovery, storageIssue.isEmpty,
              let dayOff = WeekendSchedule.snapshot(configuration: configuration, cached: snapshot, habits: catalog, now: now) else { return false }
        snapshot = dayOff
        return true
    }
    private func safeMessage(_ error: Error) -> String {
        // Never show server response bodies, request headers, or the submitted API key.
        if let error = error as? APIError { return error.localizedDescription }
        if let error = error as? GateError { return error.localizedDescription }
        if (error as NSError).domain == NSURLErrorDomain { return "Cannot reach Habitify. Retrying automatically; only verified completion remains valid until 4 AM." }
        return "Could not complete the operation. Check the connection and local storage, then retry."
    }
    private func updateCatalog(_ habits: [Habit]) throws {
        guard catalog != habits else { return }
        try GateFiles.write(habits, "catalog.json", root: root)
        catalog = habits
    }
    @discardableResult private func persistSnapshot() -> Bool {
        snapshot.guardedApps = configuration.active?.apps ?? []
        temporaryAccess.verifyStorage()
        refreshDailyAccess()
        statusChanged?()
        guard lastPersisted != snapshot else { return true }
        do { try GateFiles.write(snapshot, "snapshot.json", root: root) }
        catch {
            snapshot.access = "blocked"
            storageIssue = "Protection state could not be saved. Access is locked on this Mac; Chrome coverage needs a storage check. Free disk space or restore write access, then retry."
            refreshDailyAccess()
            message = storageIssue; statusChanged?(); return false
        }
        lastPersisted = snapshot
        if storageIssue.hasPrefix("Protection state could not be saved.") { storageIssue = "" }
        statusChanged?()
        return true
    }
    private func commitConfiguration(_ next: Configuration, restoring: Bool = false) throws {
        guard !needsRecovery || restoring else { throw GateError.invalid("Restore saved rules before changing settings.") }
        do {
            let backedUp = try ConfigurationRepository.save(next, root: root)
            storageIssue = backedUp ? "" : "Rules were saved, but their recovery copy could not be refreshed. Check local storage."
        } catch {
            storageIssue = "Rules were not saved. Your existing rules remain active. Free disk space or restore write access, then save again."
            throw GateError.invalid(storageIssue)
        }
    }
    func chooseRecoveryBackup() {
        let panel = NSOpenPanel(); panel.title = "Choose your Habit Gate rules backup"
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let candidate = try GateFiles.decoder().decode(Configuration.self, from: Data(contentsOf: url))
            try ConfigurationRepository.validate(candidate)
            guard candidate.active != nil else { throw GateError.invalid("Choose a backup containing an active rule set.") }
            configuration = candidate
            message = "Backup loaded for review. Check Active essentials, Websites and Mac apps, then choose Restore saved rules. Access stays locked."
        } catch { message = "That file is not a valid Habit Gate rules backup. Your existing files were not changed." }
    }
    func restoreSavedRules() {
        do {
            guard configuration.active != nil else { throw GateError.invalid("No complete rule set could be recovered. Restore a private configuration backup from the support folder before continuing.") }
            if needsRecovery {
                let original = root.appendingPathComponent("configuration.json")
                if FileManager.default.fileExists(atPath: original.path) {
                    try FileManager.default.copyItem(at: original, to: root.appendingPathComponent("configuration.unreadable-\(UUID().uuidString).json"))
                }
            }
            try commitConfiguration(configuration, restoring: true); needsRecovery = false
            snapshot = .locked(domains: configuration.active?.domains ?? DomainRules.defaults, reason: "Rules restored. Checking Habitify.")
            lastAttempt = .distantPast; retryAt = .distantPast; tick(forceSync: true)
        } catch { message = error.localizedDescription }
    }
    func disconnect(deleteKey: Bool) async {
        do {
            var next = configuration; next.disconnected = true
            try commitConfiguration(next); configuration = next
            await credentials.disconnect(deleteKey: deleteKey)
            credentialState = credentials.state; hasKey = false
            snapshot = .locked(domains: configuration.active?.domains ?? DomainRules.defaults, reason: "Habitify disconnected. Your rules remain active; reconnect to verify completion.")
            persistSnapshot()
            message = deleteKey ? "Disconnected. The saved API key was deleted from this Mac." : "Disconnected. The API key remains in Keychain for reconnection."
            if case .unavailable(let issue) = credentialState { message = issue }
        } catch { message = safeMessage(error) }
    }
    func reconnectSavedKey() async {
        do {
            var next = configuration; next.disconnected = nil
            try commitConfiguration(next); configuration = next
            await restoreCredentials()
        } catch { message = safeMessage(error) }
    }
    func checkProtection() { tick(); message = "Coverage checks are reported by each detected Chrome profile. Open its extension and use Test protection for a live check. Other profiles and browsers are not covered automatically." }
    func setNotifications(_ enabled: Bool) {
        var next = configuration; next.notifyOnUnlock = enabled
        do { try commitConfiguration(next); configuration = next }
        catch { return }
        if enabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
    }
    func setWeekendsOff(_ enabled: Bool) {
        guard !needsRecovery else { return }
        var next = configuration; next.weekendsOff = enabled ? true : nil
        do { try commitConfiguration(next); configuration = next }
        catch { return }
        tick(forceSync: true)
    }
    private func notify() {
        let c = UNMutableNotificationContent(); c.title = "Your essential habits are complete"; c.body = "Your selected websites and Mac apps are unlocked until 4 AM."
        UNUserNotificationCenter.current().add(.init(identifier: "unlock-\(snapshot.habitDate)", content: c, trigger: nil))
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
        } catch { message = "Could not change launch at login: \(error.localizedDescription)" }
    }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func openHabitify() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "co.vuvo.habitify") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, _ in }
        } else { NSWorkspace.shared.open(URL(string: "https://app.habitify.me/")!) }
    }
    func showExtensionFolder() {
        NSWorkspace.shared.open(GateFiles.root.appendingPathComponent("ChromeExtension", isDirectory: true))
    }
}
