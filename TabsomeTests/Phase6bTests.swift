import CoreGraphics
import Foundation
import Testing
@testable import Tabsome

/// App badges on tabs (PLAN.md §5.14, §7 Phase 6b).
struct AppBadgesTests {
    let mail = AppBadges.App(pid: 1, bundleURL: URL(fileURLWithPath: "/System/Applications/Mail.app"), name: "Mail")
    let slack = AppBadges.App(pid: 2, bundleURL: URL(fileURLWithPath: "/Applications/Slack.app"), name: "Slack")

    @Test func matchesDockItemsByTheAppsBundle() {
        let items = [
            DockItem(url: URL(fileURLWithPath: "/System/Applications/Mail.app/"), title: "Mail", badge: "12"),
            DockItem(url: URL(fileURLWithPath: "/Applications/Slack.app"), title: "Slack", badge: nil),
        ]
        #expect(AppBadges.badges(items: items, apps: [mail, slack]) == [1: "12"])
    }

    @Test func aSameNamedItemFromAnotherBundleDoesntCount() {
        let items = [DockItem(url: URL(fileURLWithPath: "/Applications/Old/Mail.app"), title: "Mail", badge: "3")]
        #expect(AppBadges.badges(items: items, apps: [mail]).isEmpty)
    }

    @Test func fallsBackToTheNameOnlyForItemsWithoutAURL() {
        let items = [DockItem(url: nil, title: "Slack", badge: "!")]
        let noBundle = AppBadges.App(pid: 3, bundleURL: nil, name: "Slack")
        #expect(AppBadges.badges(items: items, apps: [noBundle]) == [3: "!"])
    }

    @Test func blankBadgesAreIgnoredAndLongOnesShortened() {
        let items = [
            DockItem(url: URL(fileURLWithPath: "/System/Applications/Mail.app"), title: "Mail", badge: "  "),
            DockItem(url: URL(fileURLWithPath: "/Applications/Slack.app"), title: "Slack", badge: "12345"),
        ]
        #expect(AppBadges.badges(items: items, apps: [mail, slack]) == [2: "12345"])
    }

    @Test func bigCountsCapInsteadOfBeingCutOff() {
        #expect(AppBadges.display("12345") == "9999+")
        #expect(AppBadges.display("9999") == "9999")
        #expect(AppBadges.display("1,234") == "1,234")
        #expect(AppBadges.display("128", compact: true) == "99+")
        #expect(AppBadges.display("42", compact: true) == "42")
        #expect(AppBadges.display("Update") == "Upd…")
        #expect(AppBadges.display("New", compact: true) == "New")
        #expect(AppBadges.display("!", compact: true) == "!")
    }
}

@MainActor
final class FakeDockSource: DockBadgeSource {
    var items: [DockItem] = []
    private(set) var reads = 0

    func read(_ done: @escaping @MainActor ([DockItem]?) -> Void) {
        reads += 1
        done(items)
    }
}

@MainActor
struct BadgeMonitorTests {
    @Test func readsAtOnceThenOnATimerAndStopsWhenInactive() async throws {
        let source = FakeDockSource()
        source.items = [DockItem(url: nil, title: "Mail", badge: "1")]
        let monitor = BadgeMonitor(interval: 0.05)
        monitor.source = source
        var changes = 0
        monitor.onChange = { _ in changes += 1 }

        monitor.isActive = true
        #expect(source.reads == 1)
        #expect(monitor.items.count == 1)
        try await Task.sleep(for: .milliseconds(300))
        #expect(source.reads >= 3)
        #expect(changes == 1) // the same items again aren't a change

        monitor.isActive = false
        #expect(!monitor.isRunning)
        #expect(monitor.items.isEmpty)
        let reads = source.reads
        try await Task.sleep(for: .milliseconds(200))
        #expect(source.reads == reads)
    }
}

@MainActor
struct BadgeTimerLifetimeTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager
    let source = FakeDockSource()

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.windowBounds = { _ in nil }
        manager.badges.source = source
        registry.track(.init(pid: 101, name: "Mail", bundleID: "com.apple.mail"))
        registry.track(.init(pid: 202, name: "Finder", bundleID: "com.apple.finder"))
        system.send(.appWindows(101, [snapshot(1, pid: 101, frame: CGRect(x: 100, y: 100, width: 800, height: 600))]))
        system.send(.appWindows(202, [snapshot(2, pid: 202, frame: CGRect(x: 1000, y: 200, width: 500, height: 400))]))
    }

    @Test func theDockIsReadOnlyWhileAGroupExists() {
        #expect(!manager.badges.isRunning)
        #expect(source.reads == 0)
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        #expect(manager.badges.isRunning)
        #expect(source.reads == 1)
        system.send(.windowDestroyed(202, 2)) // the group drops to one window and dissolves
        #expect(manager.group(containing: 1) == nil)
        #expect(!manager.badges.isRunning)
    }
}
