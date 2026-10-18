import Foundation

public struct HabitDay {
    public let date: String
    public let start: Date
    public let end: Date
    public init(now: Date, calendar: Calendar = .current) {
        let calendar = Self.gregorian(calendar)
        let midnight = calendar.startOfDay(for: now)
        let boundary = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: midnight)!
        let anchor = now < boundary ? calendar.date(byAdding: .day, value: -1, to: midnight)! : midnight
        start = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: anchor)!
        end = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 1, to: anchor)!)!
        date = Self.string(anchor, calendar: calendar)
    }
    public static func string(_ date: Date, calendar: Calendar) -> String {
        let calendar = gregorian(calendar)
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func parse(_ text: String, calendar: Calendar) -> Date? {
        let calendar = gregorian(calendar)
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        guard let value = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              string(value, calendar: calendar) == text else { return nil }
        return value
    }
    public static func gregorian(_ calendar: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = calendar.timeZone
        return result
    }
}
public enum GateError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
}
public enum DomainRules {
    public static let defaults = ["facebook.com", "instagram.com", "x.com", "twitter.com", "fb.com"]
    public static func normalize(_ input: String) throws -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasSuffix(".") { text.removeLast() }
        if text.hasPrefix("*.") { text = String(text.dropFirst(2)) }
        guard text.count <= 253, !text.contains(":"), text.contains("."),
              text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  (1...63).contains(label.count) && label.first != "-" && label.last != "-" &&
                  label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
              }), text.split(separator: ".").last!.contains(where: \.isLetter),
              text != "habitify.me", !text.hasSuffix(".habitify.me") else {
            throw GateError.invalid("Enter a domain such as reddit.com, without a URL or path. Habitify must remain accessible.")
        }
        return text
    }
    public static func matches(host: String, domain: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || host.hasSuffix("." + domain)
    }
    public static func validated(_ domains: [String]) throws -> [String] {
        let result = try Array(Set(domains.map(normalize))).sorted()
        guard !result.isEmpty, result.count <= 50 else { throw GateError.invalid("Choose between 1 and 50 website domains.") }
        return result
    }
}
public enum PolicyEngine {
    public static func due(_ habit: Habit, on date: String, calendar: Calendar) throws -> Bool {
        let calendar = HabitDay.gregorian(calendar)
        guard habit.supported, let day = HabitDay.parse(date, calendar: calendar),
              let start = HabitDay.parse(habit.startDate, calendar: calendar) else {
            throw GateError.invalid("This habit needs a supported daily goal and schedule.")
        }
        if let end = habit.endCondition {
            guard end.type == "date", let text = end.date, let endDate = HabitDay.parse(text, calendar: calendar) else {
                throw GateError.invalid("This habit has an unsupported end condition.")
            }
            if day > endDate { throw GateError.invalid("This selected habit has ended. Update your rules for the next habit day.") }
        }
        guard day >= start else { return false }
        switch habit.occurrence.type {
        case "daily": return true
        case "weekDays":
            guard let days = habit.occurrence.days, !days.isEmpty, days.allSatisfy({ (0...6).contains($0) }) else {
                throw GateError.invalid("Invalid weekday schedule.")
            }
            return days.contains(calendar.component(.weekday, from: day) - 1)
        case "monthDays":
            guard let days = habit.occurrence.days, !days.isEmpty, days.allSatisfy({ (1...31).contains($0) }) else {
                throw GateError.invalid("Invalid monthly schedule.")
            }
            return days.contains(calendar.component(.day, from: day))
        case "interval":
            guard let interval = habit.occurrence.interval, interval > 0 else { throw GateError.invalid("Invalid interval schedule.") }
            return (calendar.dateComponents([.day], from: start, to: day).day! % interval) == 0
        default: throw GateError.invalid("Unsupported habit schedule.")
        }
    }
    public static func evaluate(policy: Policy, habits: [Habit], journal: [JournalEntry], now: Date,
                                calendar: Calendar = .current) -> GateSnapshot {
        let day = HabitDay(now: now, calendar: calendar)
        var result = GateSnapshot.locked(now: now, calendar: calendar, domains: policy.domains)
        guard !policy.habitIDs.isEmpty else { return result }
        var problem = false
        for id in Set(policy.habitIDs).sorted() {
            guard let habit = habits.first(where: { $0.id == id }) else {
                result.habits.append(.init(id: id, name: "Unavailable habit", status: "configuration", detail: "Selected habit is missing. Review your rules.")); problem = true; continue
            }
            do {
                let isDue = try due(habit, on: day.date, calendar: calendar)
                guard isDue else {
                    result.habits.append(.init(id: id, name: habit.name, status: "notDue", detail: "Not scheduled for this habit date", due: false)); continue
                }
                let entries = journal.filter { $0.id == id }
                let entry = entries.count == 1 ? entries[0] : nil
                let known = ["completed", "skipped", "failed", "inprogress"].contains(entry?.status ?? "")
                let detail: String
                if let p = entry?.progress { detail = "\(p.current.formatted()) / \(p.target.formatted()) \(p.unit)" }
                else { detail = known ? "" : "Completion could not be verified" }
                result.habits.append(.init(id: id, name: habit.name, status: known ? entry!.status : "unknown", detail: detail))
            } catch {
                problem = true
                result.habits.append(.init(id: id, name: habit.name, status: "configuration", detail: error.localizedDescription))
            }
        }
        result.lastSyncedAt = now
        let allowed = !problem && result.remainingCount == 0
        result.access = allowed ? "allowed" : "blocked"
        result.reason = problem ? "A selected habit needs attention. Access remains blocked." :
            allowed ? (result.dueCount == 0 ? "No selected habits are scheduled for this habit day." : "Your essential habits are complete.") :
            "Complete your remaining essential habits in Habitify."
        return result
    }
}
