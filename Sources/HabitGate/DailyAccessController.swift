import Foundation
import Darwin
import UserNotifications
import GateCore

func continuousSeconds() -> TimeInterval {
    var scale = mach_timebase_info_data_t(); mach_timebase_info(&scale)
    return Double(mach_continuous_time()) * Double(scale.numer) / Double(scale.denom) / 1_000_000_000
}

@MainActor final class DailyAccessController: ObservableObject {
    @Published private(set) var budget: DailyAccessBudget
    @Published private(set) var issue = ""
    @Published private(set) var notice = ""
    @Published private(set) var accessStarted = false
    var onChange: (() -> Void)?
    private let now: () -> Date
    private let continuous: () -> TimeInterval
    private let calendar: () -> Calendar
    private let save: (DailyAccessBudget) throws -> Void
    private let schedulesActions: Bool
    private let root: URL
    private var lastStored: DailyAccessBudget?
    private var activeContinuous: Double?
    private var checkedAt: Date
    private var checkedContinuous: Double
    private var configured = Set<String>()
    private var available = false
    private var expiry: DispatchWorkItem?
    private var warning: DispatchWorkItem?
    private var warned = false
    init(root: URL, now: @escaping () -> Date = Date.init,
         continuous: @escaping () -> TimeInterval = continuousSeconds,
         calendar: @escaping () -> Calendar = { .current },
         save: ((DailyAccessBudget) throws -> Void)? = nil, schedulesActions: Bool = true) {
        self.root = root; self.now = now; self.continuous = continuous; self.calendar = calendar
        self.schedulesActions = schedulesActions
        self.save = save ?? { try DailyAccessFile.save($0, root: root) }
        let date = now(); checkedAt = date; checkedContinuous = continuous()
        let exists = FileManager.default.fileExists(atPath: root.appendingPathComponent(DailyAccessFile.name).path)
        if let loaded = DailyAccessFile.load(root: root) {
            budget = loaded; lastStored = loaded
            // An unfinished segment is charged conservatively on restart; it
            // cannot become fresh free time by quitting the guard mid-use.
            if date < loaded.savedAt {
                budget.usedSeconds = budget.totalSeconds
                issue = "The clock moved backward. Today’s allowance is locked until its reset."
            } else if date < loaded.resetsAt, let started = loaded.activeSince {
                budget.consume(date.timeIntervalSince(started))
            }
            if date >= loaded.resetsAt {
                budget = DailyAccessBudget(now: date, minutes: loaded.limitMinutes, calendar: calendar())
            }
            budget.activeSince = nil; budget.activeBundleID = nil; budget.savedAt = date
        } else {
            budget = DailyAccessBudget(now: date, calendar: calendar())
            if exists {
                budget.usedSeconds = budget.totalSeconds
                issue = "Saved allowance is unreadable. Today’s allowance stays locked; a new balance begins at 4 AM."
            }
        }
        do { try self.save(budget); lastStored = DailyAccessFile.load(root: root) ?? budget }
        catch { issue = "Daily allowance could not be saved. App access stays locked until local storage is working." }
    }
    var isCounting: Bool { accessStarted && activeContinuous != nil && issue.isEmpty && available }
    var canStart: Bool { !accessStarted && available && issue.isEmpty && remaining > 0 }
    var remaining: Double {
        let elapsed = activeContinuous.map { max(0, continuous() - $0) } ?? 0
        return max(0, budget.remainingSeconds - elapsed)
    }
    func grant() -> AppAccessGrant? {
        guard accessStarted, available, issue.isEmpty, remaining > 0 else { return nil }
        return .init(bundleIDs: configured, expiresAt: min(budget.resetsAt, now().addingTimeInterval(remaining)))
    }
    @discardableResult func startAccess() -> Bool {
        guard canStart else { return false }
        let date = now(); let clock = continuous()
        guard date < budget.resetsAt else { return false }
        var next = budget; next.activeSince = date; next.activeBundleID = nil; next.savedAt = date
        guard persist(next) else { onChange?(); return false }
        budget = next; activeContinuous = clock; accessStarted = true
        notice = "Access is on. The countdown continues until you end access or today’s time runs out."
        schedule()
        onChange?(); return true
    }
    func endAccess() {
        settle(date: now(), clock: continuous())
        accessStarted = false; schedule()
        notice = "Access ended. Your remaining daily time is saved for later."
        onChange?()
    }
    func refresh(configured: Set<String>, normalAccess: Bool, recovery: Bool) {
        let date = now(); let clock = continuous()
        let previousAvailable = available
        let previouslyStarted = accessStarted
        let previousConfigured = self.configured
        self.configured = configured
        available = !normalAccess && !recovery && !configured.isEmpty
        let rollback = date.timeIntervalSince(checkedAt) < clock - checkedContinuous - 2 || clock < checkedContinuous
        checkedAt = date; checkedContinuous = clock
        if rollback {
            exhaust("The clock moved backward. Today’s allowance is locked until its reset.")
            return
        }
        if date >= budget.resetsAt, date >= budget.savedAt {
            let minutes = budget.limitMinutes
            budget = DailyAccessBudget(now: date, minutes: minutes, calendar: calendar())
            accessStarted = false
            activeContinuous = nil; issue = ""; notice = ""; warned = false
            if !persist() { available = false }
            schedule(); onChange?()
        }
        if accessStarted && (!available || !issue.isEmpty || remaining <= 0) {
            let exhausted = remaining <= 0
            settle(date: date, clock: clock)
            accessStarted = false
            if exhausted { notice = "Today’s allowance is used up. Complete your essentials or wait until 4 AM." }
            schedule(); onChange?()
        } else if previousAvailable != available || previouslyStarted != accessStarted || previousConfigured != configured { onChange?() }
        warnIfNeeded()
    }
    func verifyStorage() {
        guard let lastStored else { return }
        guard DailyAccessFile.load(root: root) == lastStored else {
            exhaust("Saved allowance changed or became unreadable. Today’s allowance is locked."); return
        }
    }
    @discardableResult func setMinutes(_ minutes: Int) -> Bool {
        guard (1...120).contains(minutes), issue.isEmpty else { return false }
        var next = budget; next.limitMinutes = minutes
        // Keep the active interval intact: changing the preference cannot refill
        // today's shared balance or restart its running segment.
        next.savedAt = now()
        guard persist(next) else { onChange?(); return false }
        budget = next
        notice = "Daily allowance saved. \(minutes) minutes applies at the next 4 AM reset."
        onChange?(); return true
    }
    func retryStorage() {
        guard issue.hasPrefix("Daily allowance could not be saved.") else { return }
        budget.activeSince = nil; budget.activeBundleID = nil; budget.savedAt = now()
        if persist() { issue = ""; notice = "Saved allowance restored. Today’s used time is unchanged." }
        onChange?()
    }
    private func settle(date: Date, clock: Double) {
        guard let started = activeContinuous else { return }
        budget.consume(clock - started)
        activeContinuous = nil; budget.activeSince = nil; budget.activeBundleID = nil
        budget.savedAt = min(date, budget.resetsAt.addingTimeInterval(-0.001))
        _ = persist()
    }
    @discardableResult private func persist(_ candidate: DailyAccessBudget? = nil) -> Bool {
        let value = candidate ?? budget
        do { try save(value); lastStored = DailyAccessFile.load(root: root) ?? value; return true }
        catch {
            issue = "Daily allowance could not be saved. App access is locked; the balance was not extended."
            if let started = activeContinuous { budget.consume(continuous() - started) }
            budget.activeSince = nil; budget.activeBundleID = nil
            accessStarted = false; activeContinuous = nil; expiry?.cancel(); warning?.cancel(); return false
        }
    }
    private func exhaust(_ text: String) {
        accessStarted = false; activeContinuous = nil; budget.usedSeconds = budget.totalSeconds
        budget.activeSince = nil; budget.activeBundleID = nil; budget.savedAt = min(now(), budget.resetsAt.addingTimeInterval(-0.001))
        issue = text; expiry?.cancel(); warning?.cancel(); _ = persist(); onChange?()
    }
    private func schedule() {
        expiry?.cancel(); warning?.cancel(); expiry = nil; warning = nil
        guard schedulesActions, isCounting else { return }
        let finish = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refresh(configured: self.configured, normalAccess: false, recovery: false)
        }
        expiry = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + min(remaining, max(0, budget.resetsAt.timeIntervalSince(now()))), execute: finish)
        if remaining > 60, !warned {
            let warn = DispatchWorkItem { [weak self] in self?.warnIfNeeded() }
            warning = warn
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining - 60, execute: warn)
        }
    }
    private func warnIfNeeded() {
        guard isCounting, remaining <= 60, !warned else { return }
        warned = true; notice = "One minute of today’s allowance remains. Finish your task soon."
        guard schedulesActions else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent(); content.title = "One minute of app access left today"
            content.body = "End access to save unused time. App windows hide when time runs out; background work may continue."
            UNUserNotificationCenter.current().add(.init(identifier: "daily-access-warning", content: content, trigger: nil))
        }
    }
}
