import Foundation
import Testing
@testable import GateCore

struct HabitCatalogTests {
    @Test func pickerExcludesArchivedAndWeeklyEntriesWithoutDiscardingAPIMetadata() {
        let daily = Habit(id: "daily", name: "Read")
        let archived = Habit(id: "old-run", name: "Run", isArchived: true, goals: [.init(periodicity: "weekly")])
        let weekly = Habit(id: "weekly", name: "Workout", goals: [.init(periodicity: "weekly")])
        let catalog = [archived, weekly, daily]
        #expect(HabitCatalog.pickerRows(catalog, selected: []).map(\.id) == ["daily"])
        #expect(catalog.count == 3)
        #expect(catalog.first?.isArchived == true)
    }

    @Test func unavailableSelectionsRemainRepairableAndCannotUnlock() {
        let archived = Habit(id: "old-run", name: "Run", isArchived: true)
        let weekly = Habit(id: "weekly", name: "Workout", goals: [.init(periodicity: "weekly")])
        let selected: Set<String> = [archived.id, weekly.id]
        let rows = HabitCatalog.pickerRows([archived, weekly], selected: selected)
        #expect(Set(rows.map(\.id)) == selected)
        #expect(HabitCatalog.selectionDetail(archived).contains("Archived in Habitify"))
        #expect(HabitCatalog.selectionDetail(weekly).contains("Weekly goal"))
        let proof = PolicyEngine.evaluate(policy: .init(habitIDs: Array(selected)), habits: [archived, weekly],
            journal: selected.map { .init(id: $0, status: "completed") }, now: Date())
        #expect(proof.access == "blocked")
        #expect(proof.habits.allSatisfy { $0.status == "configuration" })
    }
}
