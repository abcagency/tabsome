import CoreGraphics
import Foundation
import Testing
@testable import Tabsome

struct SecurityListTests {
    let window = snapshot(1, pid: 1)

    @Test func securityAppsAreNeverTabbedEvenIfTheUsersListIsEmpty() {
        for id in ["com.apple.SecurityAgent", "com.apple.keychainaccess", "com.1password.1password", "com.bitwarden.desktop", "com.apple.Passwords"] {
            #expect(!Eligibility.canTab(window, bundleID: id, excluded: []))
        }
        #expect(!Eligibility.canTab(window, bundleID: Bundle.main.bundleIdentifier, excluded: []))
    }

    @Test func theUsersListAddsToIt() {
        #expect(Eligibility.canTab(window, bundleID: "com.apple.Safari", excluded: []))
        #expect(!Eligibility.canTab(window, bundleID: "com.apple.Safari", excluded: ["com.apple.Safari"]))
    }

    @Test func systemSettingsIsExcludedByDefault() {
        #expect(ExcludedApps.defaultBundleIDs.contains("com.apple.systempreferences"))
    }
}

struct FightDetectorTests {
    @Test func moreThanThreeMovesBackInTwoSecondsIsAFight() {
        var f = FightDetector()
        let results = [0, 0.3, 0.6, 0.9].map { f.record(1, now: $0) }
        #expect(results == [false, false, false, true])
    }

    @Test func occasionalMovesAreNot() {
        var f = FightDetector()
        let results = stride(from: 0.0, through: 10, by: 0.8).map { f.record(1, now: $0) }
        #expect(!results.contains(true))
    }

    @Test func windowsAreCountedSeparately() {
        var f = FightDetector()
        for t in [0.0, 0.2, 0.4] { _ = f.record(1, now: t) }
        let other = f.record(2, now: 0.5)
        let same = f.record(1, now: 0.5)
        #expect(!other)
        #expect(same)
    }
}

@MainActor
struct FightAndExclusionTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.settleDuration = 0
        manager.windowBounds = { _ in nil }
        manager.usableArea = { _ in CGRect(x: 0, y: 25, width: 1600, height: 1000) }
        registry.track(.init(pid: 101, name: "Safari", bundleID: "com.apple.Safari"))
        registry.track(.init(pid: 202, name: "Finder", bundleID: "com.apple.finder"))
        registry.track(.init(pid: 303, name: "Notes", bundleID: "com.apple.Notes"))
        system.send(.appWindows(101, [snapshot(1, pid: 101, frame: CGRect(x: 100, y: 100, width: 800, height: 600))]))
        system.send(.appWindows(202, [snapshot(2, pid: 202, frame: CGRect(x: 1000, y: 200, width: 500, height: 400))]))
        system.send(.appWindows(303, [snapshot(3, pid: 303, frame: CGRect(x: 50, y: 50, width: 300, height: 300))]))
    }

    @Test func aWindowThatKeepsBeingMovedBackLeavesItsGroup() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        manager.merge(dragged: 3, into: 2, dropFrame: nil, snapshot: nil)
        var notice: String?
        manager.onFight = { name, _ in notice = name }
        // Something puts Safari (a background tab) back where it was, right after each placement.
        for _ in 0..<4 {
            system.send(.windowUpdated(snapshot(1, pid: 101, frame: CGRect(x: 100, y: 100, width: 800, height: 600))))
            system.send(.windowUpdated(snapshot(1, pid: 101, frame: CGRect(x: 104, y: 160, width: 790, height: 590))))
        }
        #expect(manager.group(containing: 1) == nil)
        #expect(manager.group(containing: 2) != nil)
        #expect(notice == "Safari")
        #expect(!system.commands.contains { $0.0 == .close })
    }

    @Test func excludingAnAppTakesItsWindowsOutOfGroups() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        manager.merge(dragged: 3, into: 2, dropFrame: nil, snapshot: nil)
        manager.removeExcluded(["com.apple.finder"])
        #expect(manager.group(containing: 2) == nil)
        #expect(try #require(manager.group(containing: 1)).members == [1, 3])
        #expect(!system.commands.contains { $0.0 == .close })
    }

    @Test func excludedWindowsArentOfferedByPlus() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        let gid = try #require(manager.group(containing: 1)).id
        let saved = ExcludedApps.list
        defer { ExcludedApps.list = saved }
        ExcludedApps.list = ["com.apple.Notes"]
        #expect(manager.addCandidates(for: gid).isEmpty)
    }
}
