import Foundation
import Darwin

/// An ephemeral exception for native apps only; never sent to the browser.
public struct AppAccessGrant: Equatable {
    public var bundleIDs: Set<String>
    public var expiresAt: Date
    public init(bundleIDs: Set<String>, expiresAt: Date) { self.bundleIDs = bundleIDs; self.expiresAt = expiresAt }
    public func allows(_ bundleID: String, at now: Date) -> Bool {
        now < expiresAt && bundleIDs.contains(bundleID.lowercased())
    }
}

/// One shared daily foreground-use balance, independent of habit completion.
public struct DailyAccessBudget: Codable, Equatable {
    public var version = 1
    public var limitMinutes: Int
    public var todayMinutes: Int
    public var habitDate: String
    public var resetsAt: Date
    public var usedSeconds: Double
    public var activeSince: Date?
    public var activeBundleID: String?
    public var savedAt: Date
    public init(now: Date, minutes: Int = 15, calendar: Calendar = .current) {
        let day = HabitDay(now: now, calendar: calendar)
        limitMinutes = minutes; todayMinutes = minutes; habitDate = day.date
        resetsAt = day.end; usedSeconds = 0; savedAt = now
    }
    public static func minutes(_ input: String) -> Int? {
        guard !input.isEmpty, input.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(input), (1...120).contains(value) else { return nil }
        return value
    }
    public var totalSeconds: Double { Double(todayMinutes * 60) }
    public var remainingSeconds: Double { max(0, totalSeconds - usedSeconds) }
    public var wellFormed: Bool {
        version == 1 && (1...120).contains(limitMinutes) && (1...120).contains(todayMinutes) &&
        usedSeconds.isFinite && usedSeconds >= 0 && usedSeconds <= totalSeconds &&
        habitDate.count == 10 && resetsAt > savedAt && resetsAt.timeIntervalSince(savedAt) <= 27 * 3600 &&
        (activeSince == nil) == (activeBundleID == nil) &&
        (activeBundleID.map { AppRules.selectable($0) && $0 == $0.lowercased() } ?? true) &&
        (activeSince.map { $0 <= savedAt && savedAt.timeIntervalSince($0) <= 27 * 3600 } ?? true)
    }
    public mutating func consume(_ seconds: Double) { usedSeconds = min(totalSeconds, usedSeconds + max(0, seconds)) }
}

public enum DailyAccessFile {
    public static let name = "daily-access.json"
    public static func load(root: URL) -> DailyAccessBudget? {
        let url = root.appendingPathComponent(name)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let data = try? Data(contentsOf: url), data.count <= 32_768 else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let value = try? decoder.decode(DailyAccessBudget.self, from: data), value.wellFormed else { return nil }
        return value
    }
    public static func save(_ value: DailyAccessBudget, root: URL) throws {
        guard value.wellFormed else { throw GateError.invalid("Invalid daily allowance.") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = root.appendingPathComponent(".daily-access-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        try handle.write(contentsOf: encoder.encode(value)); try handle.synchronize()
        guard rename(temporary.path, root.appendingPathComponent(name).path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
