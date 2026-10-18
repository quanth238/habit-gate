import Foundation
import Testing
@testable import GateCore
struct ParityTests {
    struct Case: Decodable { var name: String; var now: Date; var timezone: String; var snapshot: GateSnapshot; var allowed: Bool }
    @Test func nativeAndBrowserUseTheSameProofFixtures() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("proof-cases.json")
        let fixtures = try GateFiles.decoder().decode([Case].self, from: Data(contentsOf: url))
        for fixture in fixtures {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: fixture.timezone)!
            #expect((fixture.snapshot.access == "allowed" && fixture.snapshot.valid(at: fixture.now, calendar: calendar)) == fixture.allowed, Comment(rawValue: fixture.name))
        }
    }
}
