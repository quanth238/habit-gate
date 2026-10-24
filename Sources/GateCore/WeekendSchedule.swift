import Foundation

public enum WeekendSchedule {
    public static let source = "weekendSchedule"
    public static func isWeekend(at now: Date, calendar: Calendar = .current) -> Bool {
        let weekday = HabitDay.gregorian(calendar).component(.weekday, from: HabitDay(now: now, calendar: calendar).start)
        return weekday == 7 || weekday == 1
    }
    public static func snapshot(configuration: Configuration, cached: GateSnapshot?, habits: [Habit] = [],
                                now: Date = Date(), calendar: Calendar = .current) -> GateSnapshot? {
        guard configuration.weekendsOff == true, let policy = configuration.active,
              !policy.habitIDs.isEmpty, isWeekend(at: now, calendar: calendar) else { return nil }
        // Reuse a current proof instead of writing a new timestamp every tick.
        if let cached, cached.isWeekendDayOff, cached.valid(at: now, calendar: calendar),
           Set(cached.habits.map(\.id)) == Set(policy.habitIDs), cached.domains == policy.domains,
           cached.guardedApps == policy.apps { return cached }
        var result = GateSnapshot.locked(now: now, calendar: calendar, domains: policy.domains)
        result.access = "allowed"
        result.reason = "Weekend day off. No habit restrictions. Weekday rules resume Monday at 4 AM."
        result.verificationSource = source
        result.lastHabitifySyncedAt = cached?.verificationSource == source ? cached?.lastHabitifySyncedAt : cached?.lastSyncedAt
        result.lastSyncedAt = now // Verification of the local schedule, not a Habitify request.
        result.syncState = "scheduledDayOff"
        result.guardedApps = policy.apps
        result.habits = policy.habitIDs.sorted().map { id in
            .init(id: id, name: habits.first(where: { $0.id == id })?.name ?? cached?.habits.first(where: { $0.id == id })?.name ?? "Weekday essential",
                  status: "notDue", detail: "Weekend day off", due: false)
        }
        return result
    }
}
