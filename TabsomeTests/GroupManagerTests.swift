import CoreGraphics
import Foundation
import Testing
@testable import Tabsome

@MainActor
struct GroupManagerTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager
    let safariFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
    let finderFrame = CGRect(x: 1000, y: 200, width: 500, height: 400)
    let content = CGRect(x: 100, y: 132, width: 800, height: 568)

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        registry.track(.init(pid: 101, name: "Safari", bundleID: "com.apple.Safari"))
        registry.track(.init(pid: 202, name: "Finder", bundleID: "com.apple.finder"))
        registry.track(.init(pid: 303, name: "Notes", bundleID: "com.apple.Notes"))
        system.send(.appWindows(101, [snapshot(1, pid: 101, frame: safariFrame)]))
        system.send(.appWindows(202, [snapshot(2, pid: 202, frame: finderFrame)]))
        system.send(.appWindows(303, [snapshot(3, pid: 303, frame: CGRect(x: 50, y: 50, width: 300, height: 300))]))
    }

    func frames(_ id: CGWindowID) -> [CGRect] {
        system.commands.compactMap { cmd, window in
            if window == id, case .setFrame(let f) = cmd { return f } else { return nil }
        }
    }

    @Test func mergeShrinksTheTargetForTheStripAndStacksBothThere() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        let g = try #require(manager.group(containing: 1))
        #expect(g.members == [1, 2])
        #expect(g.activeID == 2)
        #expect(g.content == content)
        #expect(g.outer == safariFrame)
        #expect(frames(1).last == content)
        #expect(frames(2).last == content)
        // The dropped window ends up active: raised last.
        let raises = system.commands.filter { $0.0 == .raise }.map(\.1)
        #expect(raises.last == 2)
    }

    @Test func clickingATabRaisesThatWindow() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        system.clearCommands()
        manager.activate(1)
        #expect(manager.group(containing: 1)?.activeID == 1)
        #expect(system.commands.map(\.0) == [.raise])
    }

    @Test func closingTheActiveTabActivatesItsRightNeighbor() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        manager.merge(dragged: 3, into: 2, dropFrame: nil, snapshot: nil) // group target: its active tab
        manager.activate(2)
        manager.close(2)
        #expect(system.commands.last?.0 == .close)
        system.send(.windowDestroyed(202, 2)) // the app closed it
        let g = try #require(manager.group(containing: 1))
        #expect(g.members == [1, 3])
        #expect(g.activeID == 3)
    }

    @Test func aGroupOfOneDissolvesAndTheWindowGetsTheStripSpaceBack() {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        system.clearCommands()
        system.send(.windowDestroyed(202, 2))
        #expect(manager.groups.isEmpty)
        #expect(manager.group(containing: 1) == nil)
        #expect(frames(1).last == safariFrame)
    }

    @Test func tearingOutLeavesTwoNormalWindows() {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        manager.tearOffBegan(2, cursor: CGPoint(x: 400, y: 300))
        system.clearCommands()
        manager.tearOffEnded(cursor: CGPoint(x: 900, y: 500))
        #expect(manager.groups.isEmpty)
        #expect(frames(1).last == safariFrame)      // grew back
        let torn = frames(2).last
        #expect(torn?.size == content.size)          // at the group's size
        #expect(torn?.minY == CGFloat(500 - 14))   // held by its title bar under the cursor
    }

    @Test func ownMovesAreNotMistakenForTheUser() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        // AX reports the frames Tabsome just wrote (P5).
        system.send(.windowUpdated(snapshot(1, pid: 101, frame: content)))
        system.send(.windowUpdated(snapshot(2, pid: 202, frame: content)))
        let g = try #require(manager.group(containing: 1))
        #expect(g.content == content)
    }

    @Test func movingTheActiveWindowMovesTheGroup() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        system.send(.windowUpdated(snapshot(2, pid: 202, frame: content)))
        let moved = content.offsetBy(dx: 300, dy: 40)
        system.send(.windowUpdated(snapshot(2, pid: 202, frame: moved)))
        #expect(try #require(manager.group(containing: 2)).content == moved)
    }

    @Test func fullScreenTakesAWindowOutOfItsGroup() {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        var full = snapshot(2, pid: 202, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        full.isFullScreen = true
        system.send(.windowUpdated(full))
        #expect(manager.groups.isEmpty)
    }

    @Test func minimizeParksTheOthersAndMinimizesOnlyTheActiveWindow() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        let gid = try #require(manager.group(containing: 1)).id
        system.clearCommands()
        manager.minimize(gid)
        #expect(system.commands.contains { $0.0 == .setMinimized(true) && $0.1 == 2 })
        #expect(system.commands.contains { if case .setPosition = $0.0 { $0.1 == 1 } else { false } })
        #expect(!system.commands.contains { $0.0 == .setMinimized(true) && $0.1 == 1 })
    }

    @Test func quitUntabsEverythingAndClosesNothing() async throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        system.clearCommands()
        var finished = false
        manager.restoreAll(timeout: 2) { finished = true }
        #expect(finished)
        #expect(manager.groups.isEmpty)
        #expect(!system.commands.contains { $0.0 == .close })
        // The active window keeps the outer frame; the other is cascaded 22 pt.
        #expect(frames(2).last == safariFrame)
        #expect(frames(1).last == safariFrame.offsetBy(dx: 22, dy: 22))
    }

    @Test func groupedWindowsCannotBeMergedAgain() {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        let before = manager.groups
        manager.merge(dragged: 2, into: 3, dropFrame: nil, snapshot: nil)
        #expect(manager.groups == before)
    }
}
