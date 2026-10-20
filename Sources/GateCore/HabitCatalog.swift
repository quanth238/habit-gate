import Foundation

public enum HabitCatalog {
    public static func pickerRows(_ habits: [Habit], selected: Set<String>) -> [Habit] {
        // Keep unavailable selections visible so users can repair their rules.
        // The complete API catalog still reaches PolicyEngine for verification.
        habits.filter { $0.supported || selected.contains($0.id) }.sorted {
            if selected.contains($0.id) != selected.contains($1.id) { return selected.contains($0.id) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func selectionDetail(_ habit: Habit) -> String {
        if habit.isArchived { return "Archived in Habitify · remove from next day’s rules" }
        if habit.supported { return "Daily goal · follows its repeat schedule" }
        switch habit.goals.first(where: \.isActive)?.periodicity {
        case "weekly": return "Weekly goal · unavailable for daily essentials"
        case "monthly": return "Monthly goal · unavailable for daily essentials"
        default: return "Unavailable for daily essentials · review this habit in Habitify"
        }
    }
}
