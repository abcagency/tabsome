import Foundation
import Testing
@testable import Tabsome

@MainActor
struct WindowRegistryTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let safari = WindowRegistry.AppInfo(pid: 101, name: "Safari", bundleID: "com.apple.Safari")
    let notes = WindowRegistry.AppInfo(pid: 202, name: "Notes", bundleID: "com.apple.Notes")

    init() {
        registry = WindowRegistry(system: system)
        registry.track(safari)
        registry.track(notes)
    }

    @Test func trackingAsksTheWindowSystem() {
        #expect(system.tracked == [101, 202])
    }

    @Test func ignoresItsOwnProcess() {
        let own = ProcessInfo.processInfo.processIdentifier
        registry.track(.init(pid: own, name: "Tabsome", bundleID: "com.tabsome.app"))
        #expect(!system.tracked.contains(own))
    }

    @Test func appWindowsReplacesThatAppsWindowsOnly() {
        system.send(.appWindows(101, [snapshot(1, pid: 101), snapshot(2, pid: 101, main: true)]))
        system.send(.appWindows(202, [snapshot(3, pid: 202)]))
        system.send(.appWindows(101, [snapshot(2, pid: 101)]))
        #expect(Set(registry.windows.keys) == [2, 3])
        #expect(registry.mainWindow[101] == 2)
    }

    @Test func updatesMoveAndRetitleAWindow() {
        system.send(.appWindows(101, [snapshot(1, pid: 101)]))
        let moved = snapshot(1, pid: 101, title: "Other", frame: CGRect(x: 50, y: 60, width: 400, height: 300))
        system.send(.windowUpdated(moved))
        #expect(registry.windows[1]?.window == moved)
        #expect(registry.windows[1]?.app == safari)
    }

    @Test func destroyedRemovesTheWindowAndItsMainMark() {
        system.send(.appWindows(101, [snapshot(1, pid: 101, main: true)]))
        system.send(.windowDestroyed(101, 1))
        #expect(registry.windows[1] == nil)
        #expect(registry.mainWindow[101] == nil)
    }

    @Test func eventsForUntrackedAppsAreIgnored() {
        system.send(.appWindows(999, [snapshot(9, pid: 999)]))
        system.send(.windowUpdated(snapshot(8, pid: 999)))
        #expect(registry.windows.isEmpty)
    }

    @Test func untrackDropsTheAppsWindows() {
        system.send(.appWindows(101, [snapshot(1, pid: 101)]))
        system.send(.appWindows(202, [snapshot(3, pid: 202)]))
        registry.untrack(pid: 101)
        #expect(Set(registry.windows.keys) == [3])
        #expect(system.tracked == [202])
    }

    @Test func responsivenessIsTracked() {
        system.send(.appResponsiveness(101, responsive: false))
        #expect(registry.unresponsive == [101])
        system.send(.appResponsiveness(101, responsive: true))
        #expect(registry.unresponsive.isEmpty)
    }

    @Test func accessibilityDisabledIsReported() {
        var reported = false
        registry.onAccessibilityDisabled = { reported = true }
        system.send(.accessibilityDisabled)
        #expect(reported)
    }
}
