import Testing
import Foundation
import GateCore
@testable import HabitGate

@MainActor final class FakeGuardedApp: GuardedApplication {
    var bundleIdentifier: String?
    var isHidden = false
    var isActive = false
    var isTerminated = false
    var isFinishedLaunching = true
    var canHide = true
    var hideCalls = 0
    init(_ id: String, active: Bool = false) { bundleIdentifier = id; isActive = active }
    func hide() -> Bool {
        hideCalls += 1
        if canHide { isHidden = true }
        return canHide
    }
}

@Suite(.serialized) @MainActor struct AppBlockerTests {
    let target = BlockedApp(bundleID: "com.hnc.Discord", name: "Discord")
    @Test func hidesOnlySelectedAppsAndShowsGateForForeground() async throws {
        let discord = FakeGuardedApp(target.bundleID, active: true)
        let work = FakeGuardedApp("com.example.Work")
        let blocker = AppBlocker(running: { [discord, work] }, frontmost: { discord })
        var shown: [String] = []
        blocker.onBlocked = { shown.append($0.bundleID) }
        blocker.update(apps: [target], snapshot: .locked())
        #expect(discord.hideCalls == 1); #expect(work.hideCalls == 0)
        try await Task.sleep(for: .milliseconds(250))
        #expect(shown == [target.bundleID])
        blocker.update(apps: [target], snapshot: .locked())
        #expect(discord.hideCalls == 1)
    }
    @Test func newlySelectedAppIsHiddenNowAndRemovalWaitsUntilBoundary() async throws {
        let discord = FakeGuardedApp(target.bundleID)
        let added = FakeGuardedApp("ru.keepcoder.Telegram", active: true)
        let telegram = BlockedApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram")
        let blocker = AppBlocker(running: { [discord, added] }, frontmost: { added })
        let now = Date()
        var configuration = Configuration(active: .init(habitIDs: ["a"], apps: [target]))
        let snapshot = GateSnapshot.locked(now: now)
        blocker.update(apps: configuration.active!.apps, snapshot: snapshot)
        #expect(!added.isHidden)
        configuration.stage(.init(habitIDs: ["b"], apps: [target, telegram]), now: now)
        blocker.update(apps: configuration.active!.apps, snapshot: snapshot)
        #expect(added.isHidden); #expect(configuration.active?.habitIDs == ["a"])
        try await Task.sleep(for: .milliseconds(250))
        configuration.stage(.init(habitIDs: ["b"], apps: [target]), now: now)
        added.isHidden = false
        blocker.update(apps: configuration.active!.apps, snapshot: snapshot)
        #expect(added.isHidden)
        configuration.advance(now: HabitDay(now: now).end)
        added.isHidden = false
        blocker.update(apps: configuration.active!.apps, snapshot: snapshot)
        #expect(!added.isHidden)
    }
    @Test func activationRelocksAndBackgroundAppsDoNotStealFocus() async throws {
        let discord = FakeGuardedApp(target.bundleID)
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        var gates = 0; blocker.onBlocked = { _ in gates += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        try await Task.sleep(for: .milliseconds(250))
        #expect(discord.isHidden); #expect(gates == 0)
        discord.isHidden = false; discord.isActive = true
        blocker.enforce(discord)
        try await Task.sleep(for: .milliseconds(250))
        #expect(discord.hideCalls == 2); #expect(gates == 1)
    }
    @Test func verifiedUnlockAndExpiryUseTheSameProof() async throws {
        let now = Date()
        var proof = GateSnapshot.locked(now: now)
        proof.access = "allowed"; proof.lastSyncedAt = now
        let discord = FakeGuardedApp(target.bundleID, active: true)
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        blocker.update(apps: [target], snapshot: proof, now: now)
        #expect(discord.hideCalls == 0)
        blocker.update(apps: [target], snapshot: proof, now: proof.expiresAt)
        #expect(discord.hideCalls == 1)
        try await Task.sleep(for: .milliseconds(250))
        discord.isHidden = false
        blocker.update(apps: [target], snapshot: .locked(), now: now)
        #expect(discord.hideCalls == 2)
    }
    @Test func failureIsReportedAndTerminatedAppsAreIgnored() async throws {
        let discord = FakeGuardedApp(target.bundleID, active: true); discord.canHide = false
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        var issue = ""; var gates = 0
        blocker.onIssue = { issue = $0 }; blocker.onBlocked = { _ in gates += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        try await Task.sleep(for: .milliseconds(850))
        #expect(issue.contains("Could not hide Discord")); #expect(gates == 0)
        discord.isTerminated = true
        blocker.enforce(discord)
        #expect(discord.hideCalls == 3)
    }
    @Test func anotherSuccessfulHideDoesNotClearAnExistingFailure() async throws {
        let discord = FakeGuardedApp(target.bundleID); discord.canHide = false
        let other = FakeGuardedApp("com.example.Other")
        let blocker = AppBlocker(running: { [discord, other] }, frontmost: { nil })
        var issue = ""; blocker.onIssue = { issue = $0 }
        blocker.update(apps: [target, .init(bundleID: "com.example.Other", name: "Other")], snapshot: .locked())
        try await Task.sleep(for: .milliseconds(850))
        #expect(other.isHidden); #expect(issue.contains("Discord"))
        discord.canHide = true; blocker.enforce(discord)
        try await Task.sleep(for: .milliseconds(250))
        #expect(issue.isEmpty)
    }
    @Test func aConcurrentHideIsVerifiedWithoutAFalseFailure() async throws {
        let discord = FakeGuardedApp(target.bundleID, active: true); discord.canHide = false
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        var issue = ""; var gates = 0
        blocker.onIssue = { issue = $0 }; blocker.onBlocked = { _ in gates += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        discord.isHidden = true
        try await Task.sleep(for: .milliseconds(250))
        #expect(issue.isEmpty); #expect(gates == 1)
    }
    @Test func launchUnhideAndActivationBurstShowsOneNotice() async throws {
        let discord = FakeGuardedApp(target.bundleID, active: true)
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        var notices = 0; blocker.onBlocked = { _ in notices += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        for _ in 0..<3 { blocker.enforce(discord, showNotice: true) }
        try await Task.sleep(for: .milliseconds(250))
        #expect(discord.hideCalls == 1)
        #expect(notices == 1)
    }
    @Test func pendingHideCoalescesEventsAndKeepsForegroundIntent() async throws {
        let discord = FakeGuardedApp(target.bundleID); discord.canHide = false
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        var notices = 0; blocker.onBlocked = { _ in notices += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        discord.isActive = true
        for _ in 0..<3 { blocker.enforce(discord, showNotice: true) }
        discord.canHide = true
        try await Task.sleep(for: .milliseconds(500))
        #expect(discord.hideCalls == 2)
        #expect(notices == 1)
    }
    @Test func staleHiddenEventsStayQuietButANewAttemptShowsAgain() async throws {
        let discord = FakeGuardedApp(target.bundleID, active: true)
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        var notices = 0; blocker.onBlocked = { _ in notices += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        try await Task.sleep(for: .milliseconds(250))
        #expect(notices == 1)
        for _ in 0..<3 { blocker.enforce(discord, showNotice: true) }
        #expect(notices == 1)
        discord.isHidden = false
        blocker.enforce(discord, showNotice: true)
        try await Task.sleep(for: .milliseconds(250))
        #expect(discord.isHidden); #expect(discord.hideCalls == 2)
        #expect(notices == 2)
    }
    @Test func unlockCancelsOldHideVerificationBeforeAnotherAttempt() async throws {
        let oldApp = FakeGuardedApp(target.bundleID, active: true); oldApp.canHide = false
        var runningApps: [any GuardedApplication] = [oldApp]
        let blocker = AppBlocker(running: { runningApps }, frontmost: { runningApps.first })
        var notices = 0; blocker.onBlocked = { _ in notices += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        let now = Date()
        var proof = GateSnapshot.locked(now: now); proof.access = "allowed"; proof.lastSyncedAt = now
        blocker.update(apps: [target], snapshot: proof, now: now)
        let newApp = FakeGuardedApp(target.bundleID, active: true); runningApps = [newApp]
        blocker.update(apps: [target], snapshot: .locked())
        try await Task.sleep(for: .milliseconds(500))
        #expect(oldApp.hideCalls == 1)
        #expect(newApp.isHidden); #expect(newApp.hideCalls == 1)
        #expect(notices == 1)
    }
    @Test func coldLaunchWaitsForReadinessAndKeepsForegroundIntent() async throws {
        let zalo = FakeGuardedApp("com.vng.zalo", active: true)
        zalo.isFinishedLaunching = false
        let target = BlockedApp(bundleID: "com.vng.zalo", name: "Zalo")
        let blocker = AppBlocker(running: { [] }, frontmost: { nil })
        var notices = 0; blocker.onBlocked = { _ in notices += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        blocker.enforce(zalo, showNotice: true)
        try await Task.sleep(for: .milliseconds(750))
        #expect(zalo.hideCalls == 0)
        #expect(notices == 0)
        // didLaunch can arrive after the app has already lost foreground focus.
        zalo.isFinishedLaunching = true; zalo.isActive = false
        blocker.enforce(zalo)
        try await Task.sleep(for: .milliseconds(250))
        #expect(zalo.hideCalls == 1)
        #expect(notices == 1)
    }
    @Test func activationDuringQuietHideStillExplainsTheBlock() async throws {
        let discord = FakeGuardedApp(target.bundleID)
        let blocker = AppBlocker(running: { [discord] }, frontmost: { nil })
        var notices = 0; blocker.onBlocked = { _ in notices += 1 }
        blocker.update(apps: [target], snapshot: .locked())
        #expect(discord.isHidden)
        // macOS can deliver foreground intent after hide has updated visibility.
        blocker.enforce(discord, showNotice: true)
        try await Task.sleep(for: .milliseconds(250))
        #expect(discord.hideCalls == 1)
        #expect(notices == 1)
    }

    @Test func temporaryGrantCancelsPendingHideAndEndHidesImmediately() async throws {
        let discord = FakeGuardedApp(target.bundleID, active: true); discord.canHide = false
        let other = FakeGuardedApp("com.example.Other")
        let apps = [target, BlockedApp(bundleID: "com.example.Other", name: "Other")]
        let blocker = AppBlocker(running: { [discord, other] }, frontmost: { discord })
        var notices = 0; blocker.onBlocked = { _ in notices += 1 }
        blocker.update(apps: apps, snapshot: .locked())
        let now = Date()
        let grant = AppAccessGrant(bundleIDs: [target.id], expiresAt: now.addingTimeInterval(60))
        blocker.update(apps: apps, snapshot: .locked(), allowance: grant)
        discord.canHide = true
        blocker.enforce(discord, showNotice: true)
        try await Task.sleep(for: .milliseconds(500))
        #expect(discord.hideCalls == 1); #expect(!discord.isHidden)
        #expect(other.isHidden); #expect(notices == 0)
        blocker.update(apps: apps, snapshot: .locked())
        #expect(discord.isHidden); #expect(discord.hideCalls == 2)
        try await Task.sleep(for: .milliseconds(250))
        #expect(notices == 1)
        blocker.update(apps: apps, snapshot: .locked())
        #expect(discord.hideCalls == 2); #expect(!discord.isTerminated)
    }
    @Test func expiredSessionCannotExemptActivationEvenBeforeScheduledRefresh() async throws {
        let discord = FakeGuardedApp(target.bundleID, active: true)
        let blocker = AppBlocker(running: { [discord] }, frontmost: { discord })
        let now = Date()
        let grant = AppAccessGrant(bundleIDs: [target.id], expiresAt: now.addingTimeInterval(60))
        blocker.update(apps: [target], snapshot: .locked(), allowance: grant)
        #expect(!discord.isHidden)
        blocker.enforce(discord, now: grant.expiresAt)
        #expect(discord.isHidden)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!discord.isTerminated)
    }

    @Test func foregroundAccountingRunsBeforeEnforcement() async throws {
        let discord = FakeGuardedApp(target.bundleID, active: true)
        let blocker = AppBlocker(running: { [] }, frontmost: { discord })
        blocker.update(apps: [target], snapshot: .locked())
        var accounted = false
        blocker.onForeground = { id in
            accounted = id == target.bundleID
            blocker.update(apps: [target], snapshot: .locked(), allowance: .init(bundleIDs: [target.id], expiresAt: Date().addingTimeInterval(60)))
        }
        blocker.applicationEvent(discord, showNotice: true)
        #expect(accounted); #expect(discord.hideCalls == 0)
        blocker.onForeground = { _ in blocker.update(apps: [target], snapshot: .locked()) }
        blocker.applicationEvent(discord, showNotice: true)
        #expect(discord.hideCalls == 1)
        try await Task.sleep(for: .milliseconds(250))
    }

}
