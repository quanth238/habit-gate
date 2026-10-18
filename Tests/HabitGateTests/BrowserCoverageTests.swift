import Foundation
import GateCore
import Testing
@testable import HabitGate

struct BrowserCoverageTests {
    func client(_ id: String = "profile", at date: Date = Date(), permissions: Bool = true, incognito: Bool = false) -> BrowserClient {
        .init(id: id, seenAt: date, privateAccess: incognito, permissionsOK: permissions)
    }
    @Test func aHeartbeatAndFileOrderDoNotInvalidateTheInterface() {
        let now = Date()
        let old = [client("one", at: now), client("two", at: now)]
        let latest = [client("two", at: now.addingTimeInterval(30)), client("one", at: now.addingTimeInterval(30))]
        #expect(sameBrowserCoverage(old, latest))
    }
    @Test func permissionAndPrivateBrowsingChangesRemainVisible() {
        #expect(!sameBrowserCoverage([client()], [client(permissions: false)]))
        #expect(!sameBrowserCoverage([client()], [client(incognito: true)]))
    }
    @Test func disconnectedAndReplacedProfilesRemainVisible() {
        #expect(!sameBrowserCoverage([client()], []))
        #expect(!sameBrowserCoverage([client("old")], [client("new")]))
        #expect(!sameBrowserCoverage([client()], [client(), client("second")]))
    }
}
