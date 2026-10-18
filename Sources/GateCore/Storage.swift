import Foundation

public enum GateFiles {
    public static let refreshNotification = "me.habitgate.refresh"
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HabitGate", isDirectory: true)
    }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
    public static func read<T: Decodable>(_ type: T.Type, _ name: String, root: URL = root) -> T? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return nil }
        return try? decoder().decode(type, from: data)
    }
    public static func write<T: Encodable>(_ value: T, _ name: String, root: URL = root) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder().encode(value).write(to: root.appendingPathComponent(name), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: root.appendingPathComponent(name).path)
    }
    public static func browserClients(now: Date = Date()) -> [BrowserClient] {
        let directory = root.appendingPathComponent("clients")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { read(BrowserClient.self, $0.lastPathComponent, root: directory) }
            .filter { now.timeIntervalSince($0.seenAt) >= -5 && now.timeIntervalSince($0.seenAt) < 150 }
    }
    public static func writable(root: URL = root) -> Bool {
        let probe = root.appendingPathComponent(".storage-check-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try Data([1]).write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch { return false }
    }
}
