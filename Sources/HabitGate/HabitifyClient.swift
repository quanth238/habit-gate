import Foundation
import GateCore
import Security

enum APIError: LocalizedError {
    case response(Int, TimeInterval?)
    case malformed
    var errorDescription: String? {
        switch self {
        case .response(401, _): return "Habitify rejected the API key. Reconnect in Settings."
        case .response(403, _): return "Habitify API access is unavailable. Check your paid plan and API key."
        case .response(429, _): return "Habitify is rate limiting requests. Retrying automatically."
        case .response: return "Habitify is temporarily unavailable. Access uses only valid, previously verified completion."
        case .malformed: return "Habitify returned an unexpected response. Access remains blocked unless already verified for this day."
        }
    }
}
struct HabitifyClient {
    let key: String
    let session: URLSession
    private static let liveSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil
        return URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }()
    init(key: String, session: URLSession? = nil) { self.key = key; self.session = session ?? Self.liveSession }
    struct List<T: Decodable>: Decodable { var data: [T]; var pagination: Pagination? }
    struct Pagination: Decodable { var total: Int; var limit: Int; var offset: Int }
    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: "https://api.habitify.me/v2/\(path)")!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"; request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.malformed }
        guard (200...299).contains(response.statusCode) else {
            var wait = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            if wait == nil, let header = response.value(forHTTPHeaderField: "Retry-After") {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; wait = f.date(from: header)?.timeIntervalSinceNow
            }
            throw APIError.response(response.statusCode, wait)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.malformed }
    }
    func habits() async throws -> [Habit] {
        var all: [Habit] = []; var offset = 0
        for _ in 0..<100 {
            let page: List<Habit> = try await get("habits", query: [.init(name: "limit", value: "100"), .init(name: "offset", value: "\(offset)")])
            guard Set(page.data.map(\.id)).count == page.data.count,
                  Set(all.map(\.id)).isDisjoint(with: page.data.map(\.id)) else { throw APIError.malformed }
            all += page.data; offset += page.data.count
            if let pagination = page.pagination {
                guard pagination.offset == offset - page.data.count, pagination.total >= all.count else { throw APIError.malformed }
                if all.count >= pagination.total { return all }
                guard !page.data.isEmpty else { throw APIError.malformed }
            } else if page.data.count < 100 { return all }
        }
        throw APIError.malformed
    }
    func journal(date: String) async throws -> [JournalEntry] {
        let response: List<JournalEntry> = try await get("habits/journal", query: [.init(name: "date", value: date)])
        guard Set(response.data.map(\.id)).count == response.data.count else { throw APIError.malformed }
        return response.data
    }
}
private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The API key must never follow an HTTP redirect to another destination.
        completionHandler(nil)
    }
}
enum KeychainStore {
    static let service = "me.habitgate.habitify"
    static func delete() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GateError.invalid("Could not delete the saved Keychain item.")
        }
    }
    static func load() throws -> String? {
        // Let macOS request approval when an updated local build needs access.
        // KeychainVault runs this potentially blocking call away from the UI.
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GateError.invalid("macOS Keychain access is unavailable (\(status)).")
        }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query.merging(attributes) { _, new in new }
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(addition as CFDictionary, nil)
            guard added == errSecSuccess else { throw GateError.invalid("Could not save the key in Keychain (\(added)).") }
        } else if status != errSecSuccess { throw GateError.invalid("Could not update Keychain (\(status)).") }
    }
}
