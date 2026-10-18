import Foundation

public struct Occurrence: Codable, Equatable {
    public var type: String
    public var days: [Int]?
    public var interval: Int?
    public init(type: String, days: [Int]? = nil, interval: Int? = nil) {
        self.type = type; self.days = days; self.interval = interval
    }
}
public struct Goal: Codable, Equatable {
    public var periodicity: String
    public var isActive: Bool
    public init(periodicity: String, isActive: Bool = true) {
        self.periodicity = periodicity; self.isActive = isActive
    }
}
public struct EndCondition: Codable, Equatable {
    public var type: String
    public var date: String?
    public var isMet: Bool?
}
public struct Habit: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var type: String
    public var occurrence: Occurrence
    public var startDate: String
    public var isArchived: Bool
    public var goals: [Goal]
    public var endCondition: EndCondition?
    public var supported: Bool {
        !isArchived && type == "good" && goals.filter(\.isActive).count == 1 &&
        goals.first(where: \.isActive)?.periodicity == "daily" &&
        ["daily", "weekDays", "monthDays", "interval"].contains(occurrence.type) &&
        (endCondition == nil || endCondition?.type == "date")
    }
    public init(id: String, name: String, type: String = "good", occurrence: Occurrence = .init(type: "daily"),
                startDate: String = "2020-01-01", isArchived: Bool = false, goals: [Goal] = [.init(periodicity: "daily")], endCondition: EndCondition? = nil) {
        self.id = id; self.name = name; self.type = type; self.occurrence = occurrence
        self.startDate = startDate; self.isArchived = isArchived; self.goals = goals; self.endCondition = endCondition
    }
}
public struct JournalEntry: Codable, Equatable {
    public var id: String
    public var status: String
    public var progress: ProgressValue?
    public init(id: String, status: String, progress: ProgressValue? = nil) {
        self.id = id; self.status = status; self.progress = progress
    }
}
public struct ProgressValue: Codable, Equatable {
    public var current: Double
    public var target: Double
    public var unit: String
    public var periodicity: String
}
public struct Policy: Codable, Equatable {
    public var habitIDs: [String]
    public var domains: [String]
    public var apps: [BlockedApp]
    public init(habitIDs: [String], domains: [String] = DomainRules.defaults, apps: [BlockedApp] = []) {
        self.habitIDs = habitIDs; self.domains = domains; self.apps = apps
    }
    private enum CodingKeys: String, CodingKey { case habitIDs, domains, apps }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        habitIDs = try c.decode([String].self, forKey: .habitIDs)
        domains = try c.decode([String].self, forKey: .domains)
        apps = try c.decodeIfPresent([BlockedApp].self, forKey: .apps) ?? []
    }
}
public struct PendingPolicy: Codable, Equatable {
    public var policy: Policy
    public var effectiveAt: Date
    public var timezone: String
    public init(policy: Policy, effectiveAt: Date, timezone: String = TimeZone.current.identifier) {
        self.policy = policy; self.effectiveAt = effectiveAt; self.timezone = timezone
    }
}
public struct Configuration: Codable, Equatable {
    public var active: Policy?
    public var pending: PendingPolicy?
    public var notifyOnUnlock: Bool
    public var draft: Policy?
    public var disconnected: Bool?
    public init(active: Policy? = nil, pending: PendingPolicy? = nil, notifyOnUnlock: Bool = false) {
        self.active = active; self.pending = pending; self.notifyOnUnlock = notifyOnUnlock
    }
    public mutating func stage(_ policy: Policy, now: Date, calendar: Calendar = .current) {
        advance(now: now, calendar: calendar)
        if active == nil { active = policy; pending = nil; return }
        includeTargets(from: policy)
        pending = matchesActive(policy) ? nil : .init(policy: policy, effectiveAt: HabitDay(now: now, calendar: calendar).end,
                                                 timezone: calendar.timeZone.identifier)
    }
    public mutating func advance(now: Date, calendar: Calendar = .current) {
        guard var pending else { return }
        if pending.timezone != calendar.timeZone.identifier {
            pending.timezone = calendar.timeZone.identifier
            pending.effectiveAt = HabitDay(now: now, calendar: calendar).end
            self.pending = pending
        } else if now >= pending.effectiveAt {
            active = pending.policy; self.pending = nil; return
        }
        // Also upgrades already-saved rules: stricter website/app coverage starts
        // now; habit edits and target removals keep their original boundary.
        includeTargets(from: pending.policy)
        if matchesActive(pending.policy) { self.pending = nil }
    }
    private mutating func includeTargets(from desired: Policy) {
        guard var current = active else { return }
        for domain in desired.domains where !current.domains.contains(domain) { current.domains.append(domain) }
        for app in desired.apps where !current.apps.contains(where: { $0.id == app.id }) { current.apps.append(app) }
        active = current
    }
    private func matchesActive(_ desired: Policy) -> Bool {
        guard let active else { return false }
        return Set(active.habitIDs) == Set(desired.habitIDs) && Set(active.domains) == Set(desired.domains) &&
            Set(active.apps.map(\.id)) == Set(desired.apps.map(\.id))
    }
}
public struct HabitState: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var status: String
    public var detail: String
    public var due: Bool
    public init(id: String, name: String, status: String, detail: String = "", due: Bool = true) {
        self.id = id; self.name = name; self.status = status; self.detail = detail; self.due = due
    }
}
public struct GateSnapshot: Codable, Equatable {
    public var version: Int = 1
    public var habitDate: String
    public var timezone: String
    public var utcOffsetMinutes: Int
    public var expiresAt: Date
    public var access: String
    public var reason: String
    public var habits: [HabitState]
    public var domains: [String]
    public var lastSyncedAt: Date?
    public var syncError: String?
    public var syncState: String?
    public var guardedApps: [BlockedApp]?
    public var remainingCount: Int { habits.filter { $0.due && $0.status != "completed" }.count }
    public var dueCount: Int { habits.filter(\.due).count }
    public var completedCount: Int { habits.filter { $0.due && $0.status == "completed" }.count }
    public static func locked(now: Date = Date(), calendar: Calendar = .current, domains: [String] = DomainRules.defaults,
                              reason: String = "Connect Habitify and choose your essential habits.") -> Self {
        let day = HabitDay(now: now, calendar: calendar)
        return Self(habitDate: day.date, timezone: calendar.timeZone.identifier,
                    utcOffsetMinutes: calendar.timeZone.secondsFromGMT(for: now) / 60, expiresAt: day.end,
                    access: "blocked", reason: reason, habits: [], domains: domains)
    }
    public func valid(at now: Date, calendar: Calendar = .current) -> Bool {
        let day = HabitDay(now: now, calendar: calendar)
        return version == 1 && habitDate == day.date && utcOffsetMinutes == calendar.timeZone.secondsFromGMT(for: now) / 60 &&
            (access != "allowed" || habits.allSatisfy { $0.status != "configuration" && (!$0.due || $0.status == "completed") }) &&
            now < expiresAt && expiresAt <= day.end && (lastSyncedAt.map { $0 <= now.addingTimeInterval(5) } ?? false)
    }
    public func sanitized(at now: Date, calendar: Calendar = .current) -> Self {
        guard valid(at: now, calendar: calendar) else {
            return .locked(now: now, calendar: calendar, domains: domains, reason: "Checking the current habit day. Access stays blocked until verified.")
        }
        return self
    }
}
public struct BrowserClient: Codable, Equatable {
    public var id: String
    public var seenAt: Date
    public var privateAccess: Bool
    public var permissionsOK: Bool
    public var label: String?
    public var missingDomains: [String]?
    public var checkedDomains: [String]?
    public var extensionVersion: String?
    public var rulesOK: Bool?
    public var permissionIssue: String?
    public var testedAt: Date?
    public var testPassed: Bool?
    public init(id: String, seenAt: Date, privateAccess: Bool, permissionsOK: Bool) {
        self.id = id; self.seenAt = seenAt; self.privateAccess = privateAccess; self.permissionsOK = permissionsOK
    }
}
