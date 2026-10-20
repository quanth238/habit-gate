import Foundation
import Testing
@testable import HabitGate

final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@Suite(.serialized) struct APITests {
    func client() -> HabitifyClient {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [MockProtocol.self]
        return HabitifyClient(key: "test-placeholder-not-a-real-key", session: URLSession(configuration: c))
    }
    @Test func paginationAndReadOnlyAuthentication() async throws {
        var calls = 0
        MockProtocol.handler = { req in
            #expect(req.httpMethod == "GET"); #expect(req.url?.host == "api.habitify.me")
            #expect(req.value(forHTTPHeaderField: "X-API-Key") == "test-placeholder-not-a-real-key")
            let offset = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "offset" }!.value!
            calls += 1
            let body = """
            {"data":[{"id":"\(offset)","name":"Read","type":"good","occurrence":{"type":"daily"},"startDate":"2026-01-01","isArchived":false,"goals":[{"periodicity":"daily","isActive":true}]}],"pagination":{"total":2,"limit":1,"offset":\(offset)}}
            """
            return (200, [:], Data(body.utf8))
        }
        let habits = try await client().habits()
        #expect(habits.map(\.id) == ["0", "1"]); #expect(calls == 2)
    }
    @Test func explicitJournalDateAndPartialProgress() async throws {
        MockProtocol.handler = { req in
            #expect(req.url?.path == "/v2/habits/journal")
            #expect(URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "2026-10-17")
            return (200, [:], Data(#"{"data":[{"id":"a","status":"inprogress","progress":{"current":12,"target":20,"unit":"rep","periodicity":"daily"}}]}"#.utf8))
        }
        let entries = try await client().journal(date: "2026-10-17")
        #expect(entries.first?.status == "inprogress"); #expect(entries.first?.progress?.current == 12)
    }
    @Test func refreshedCatalogReplacesDeletedHabitsAndUsesCurrentNamesAndArchiveFlags() async throws {
        var calls = 0
        MockProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            calls += 1
            let entries = calls == 1 ? [("keep", "Old name", false), ("deleted", "Gone", false)] :
                [("keep", "Renamed", false), ("archived", "Old run", true)]
            let data = entries.map { id, name, archived in
                """
                {"id":"\(id)","name":"\(name)","type":"good","occurrence":{"type":"daily"},"startDate":"2026-01-01","isArchived":\(archived),"goals":[{"periodicity":"daily","isActive":true}]}
                """
            }.joined(separator: ",")
            return (200, [:], Data("{\"data\":[\(data)]}".utf8))
        }
        let api = client()
        let before = try await api.habits()
        let after = try await api.habits()
        #expect(before.contains { $0.id == "deleted" })
        #expect(!after.contains { $0.id == "deleted" })
        #expect(after.first { $0.id == "keep" }?.name == "Renamed")
        #expect(after.first { $0.id == "archived" }?.isArchived == true)
    }
    @Test func authRateLimitAndServerBodiesAreSanitized() async {
        for status in [401, 403, 429, 500] {
            MockProtocol.handler = { _ in (status, ["Retry-After": "90"], Data("private server body test-placeholder-not-a-real-key".utf8)) }
            do { _ = try await client().habits(); Issue.record("Expected an HTTP error") }
            catch {
                #expect(!error.localizedDescription.contains("private server body"))
                #expect(!error.localizedDescription.contains("test-placeholder"))
                if case let APIError.response(code, retry) = error { #expect(code == status); #expect(retry == 90) }
                else { Issue.record("Expected classified API error") }
            }
        }
    }
    @Test func malformedAndDuplicateEntriesAreRejected() async {
        for body in ["not json", #"{"data":[{"id":"a","status":"completed"},{"id":"a","status":"completed"}]}"#] {
            MockProtocol.handler = { _ in (200, [:], Data(body.utf8)) }
            do { _ = try await client().journal(date: "2026-10-17"); Issue.record("Expected malformed response failure") } catch { }
        }
    }
}
