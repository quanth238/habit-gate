import Foundation

public struct BlockedApp: Codable, Identifiable, Equatable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID.lowercased() }
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
}

public enum AppRules {
    private static let protectedIDs: Set<String> = [
        "me.habitgate.app", "co.vuvo.habitify", "com.apple.finder", "com.apple.systempreferences",
        "com.apple.loginwindow", "com.apple.dock", "com.apple.systemuiserver"
    ]
    public static func selectable(_ bundleID: String) -> Bool {
        let parts = bundleID.split(separator: ".", omittingEmptySubsequences: false)
        return bundleID.count <= 255 && parts.count >= 2 && !protectedIDs.contains(bundleID.lowercased()) &&
            parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }
    }
    public static func validated(_ apps: [BlockedApp]) throws -> [BlockedApp] {
        guard apps.count <= 50, apps.allSatisfy({ selectable($0.bundleID) && !$0.name.isEmpty && $0.name.count <= 200 }),
              Set(apps.map(\.id)).count == apps.count else {
            throw GateError.invalid("Choose up to 50 different apps. Habitify, Habit Gate and essential system apps must remain accessible.")
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func shouldBlock(bundleID: String?, apps: [BlockedApp], snapshot: GateSnapshot,
                                   now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let bundleID, selectable(bundleID), apps.contains(where: { $0.id == bundleID.lowercased() }) else { return false }
        return snapshot.access != "allowed" || !snapshot.valid(at: now, calendar: calendar)
    }
}
