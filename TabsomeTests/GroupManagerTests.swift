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
        manager.windowBounds = { _ in nil }
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
        manager.settleDuration = 0 // the move comes after the merge has settled
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
        manager.restoreAll(timeout: 2) { _ in finished = true }
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

@MainActor
struct GroupManagerPhase4Tests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager
    let content = CGRect(x: 100, y: 132, width: 800, height: 568)

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.windowBounds = { _ in nil }
        for (pid, name) in [(101, "Safari"), (202, "Finder"), (303, "Notes"), (404, "Mail"), (505, "Xcode")] as [(pid_t, String)] {
            registry.track(.init(pid: pid, name: name, bundleID: "test.\(name)"))
            system.send(.appWindows(pid, [snapshot(CGWindowID(pid / 101), pid: pid, frame: CGRect(x: 100, y: 100, width: 800, height: 600))]))
        }
    }

    @Test func dropOnAStripInsertsAtThatPosition() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)          // [1, 2]
        manager.merge(dragged: 3, into: 2, at: 1, dropFrame: nil, snapshot: nil)   // onto the strip, between them
        #expect(try #require(manager.group(containing: 1)).members == [1, 3, 2])
        #expect(manager.group(containing: 1)?.activeID == 3)
    }

    @Test func aWholeGroupMergesIntoAnother() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)   // A = [1, 2], active 2
        manager.merge(dragged: 4, into: 3, dropFrame: nil, snapshot: nil)   // B = [3, 4], active 4
        let b = try #require(manager.group(containing: 3)).id
        manager.mergeGroup(b, into: 2, dropFrame: nil, snapshot: nil)
        #expect(manager.groups.count == 1)
        let g = try #require(manager.group(containing: 1))
        #expect(g.members == [1, 2, 3, 4])
        #expect(g.activeID == 4)
    }

    @Test func reorderAndCloseToTheRight() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        manager.merge(dragged: 3, into: 2, dropFrame: nil, snapshot: nil)   // [1, 2, 3]
        manager.reorder(3, to: 0)
        #expect(try #require(manager.group(containing: 1)).members == [3, 1, 2])
        system.clearCommands()
        manager.closeToTheRight(1)
        #expect(system.commands.map(\.1) == [2])
        #expect(system.commands.map(\.0) == [.close])
        system.clearCommands()
        manager.closeOthers(1)
        #expect(Set(system.commands.map(\.1)) == [3, 2])
    }

    @Test func moveTabToNewWindowCascadesItOut() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        manager.merge(dragged: 3, into: 2, dropFrame: nil, snapshot: nil)
        let outer = try #require(manager.group(containing: 1)).outer
        system.clearCommands()
        manager.moveToNewWindow(3)
        #expect(manager.group(containing: 3) == nil)
        #expect(try #require(manager.group(containing: 1)).members == [1, 2])
        let frame = system.commands.compactMap { c, w -> CGRect? in if w == 3, case .setFrame(let f) = c { f } else { nil } }.last
        #expect(frame == outer.offsetBy(dx: 22, dy: 22))
    }

    @Test func plusOffersWindowsNotInTheGroup() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        let gid = try #require(manager.group(containing: 1)).id
        #expect(Set(manager.addCandidates(for: gid).map(\.id)) == [3, 4, 5])
    }
}

@MainActor
struct TuckTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.windowBounds = { _ in nil }
        registry.track(.init(pid: 101, name: "Safari", bundleID: "a"))
        registry.track(.init(pid: 202, name: "Finder", bundleID: "b"))
        system.send(.appWindows(101, [snapshot(1, pid: 101, frame: CGRect(x: 100, y: 100, width: 800, height: 600))]))
        system.send(.appWindows(202, [snapshot(2, pid: 202, frame: CGRect(x: 900, y: 100, width: 500, height: 400))]))
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil) // active 2, background 1
        system.clearCommands()
    }

    @Test func movingTheGroupTucksTheBackgroundTabThenBringsItBack() throws {
        let content = try #require(manager.group(containing: 1)).content
        let moved = content.offsetBy(dx: 200, dy: 50)
        manager.memberDragMoved(2, bounds: content.offsetBy(dx: 10, dy: 0))
        manager.memberDragMoved(2, bounds: moved)
        let positions = system.commands.filter { if case .setPosition = $0.0 { $0.1 == 1 } else { false } }
        #expect(positions.count == 1) // one write when the drag starts, none during it
        system.clearCommands()
        manager.memberDragEnded(2) // (ScreenWindows has no bounds for a fake window: the last live frame is kept)
        let back = system.commands.compactMap { c, w -> CGRect? in if w == 1, case .setFrame(let f) = c { f } else { nil } }
        #expect(back == [moved])
    }

    @Test func draggingTheStripTucksToo() throws {
        let gid = try #require(manager.group(containing: 1)).id
        manager.stripDragChanged(gid, cursor: CGPoint(x: 500, y: 110))
        manager.stripDragChanged(gid, cursor: CGPoint(x: 600, y: 150))
        #expect(system.commands.contains { if case .setPosition = $0.0 { $0.1 == 1 } else { false } })
    }
}

@MainActor
struct GroupManagerPhase4bTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager
    let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.windowBounds = { _ in nil }
        for (pid, name) in [(101, "Safari"), (202, "Finder"), (303, "Notes"), (404, "Mail"), (505, "Xcode")] as [(pid_t, String)] {
            registry.track(.init(pid: pid, name: name, bundleID: "test.\(name)"))
            system.send(.appWindows(pid, [snapshot(CGWindowID(pid / 101), pid: pid, title: "Doc \(pid)", frame: frame)]))
        }
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        manager.merge(dragged: 3, into: 2, dropFrame: nil, snapshot: nil)
        manager.merge(dragged: 4, into: 3, dropFrame: nil, snapshot: nil) // [1, 2, 3, 4], active 4
    }

    @Test func renamingFollowsTheRulesAndTheWindow() {
        manager.rename(2, to: "   Research   ")
        #expect(registry.customNames[2] == "Research")
        manager.rename(2, to: String(repeating: "x", count: 80))
        #expect(registry.customNames[2]?.count == 60)
        manager.rename(2, to: "")
        #expect(registry.customNames[2] == nil)
        manager.rename(3, to: "Notes for later")
        manager.moveToNewWindow(3)                       // the name follows the window
        #expect(registry.customNames[3] == "Notes for later")
        system.send(.windowDestroyed(303, 3))            // and goes when it closes
        #expect(registry.customNames[3] == nil)
    }

    @Test func aCustomNameWinsOverTheDefaultLabel() throws {
        let e = try #require(registry.windows[2])
        #expect(TabLabel.label(for: e, among: [e], customName: "Mine") == "Mine")
        #expect(TabLabel.label(for: e, among: [e]) == "Finder")
    }

    @Test func switchingToLeftMovesTheStripSpaceToTheLeftSide() throws {
        let outer = try #require(manager.group(containing: 1)).outer
        system.clearCommands()
        manager.setPlacement(.left)
        let g = try #require(manager.group(containing: 1))
        #expect(g.placement == .left)
        #expect(g.outer == outer)
        #expect(g.content == CGRect(x: outer.minX + 40, y: outer.minY, width: outer.width - 40, height: outer.height))
        #expect(system.commands.contains { if case .setFrame(let f) = $0.0 { f == g.content } else { false } })
    }

    @Test func severalSelectedTabsTornOutBecomeTheirOwnGroup() throws {
        manager.tearOffBegan([2, 3], grabbed: 3, cursor: CGPoint(x: 1200, y: 400))
        manager.tearOffEnded(cursor: CGPoint(x: 1200, y: 400))
        let original = try #require(manager.group(containing: 1))
        #expect(original.members == [1, 4])
        let new = try #require(manager.group(containing: 2))
        #expect(new.members == [2, 3])
        #expect(new.activeID == 3)
        #expect(new.id != original.id)
    }

    @Test func movingSelectedTabsToNewWindowMakesAGroup() throws {
        manager.moveToNewWindow([1, 2], active: 2)
        #expect(try #require(manager.group(containing: 1)).members == [1, 2])
        #expect(try #require(manager.group(containing: 3)).members == [3, 4])
    }

    @Test func shortcutsActOnTheFocusedGroup() throws {
        // No app is frontmost in tests, so there's no focused group: shortcuts do nothing.
        let before = try #require(manager.group(containing: 1)).activeID
        manager.perform(.next)
        #expect(manager.group(containing: 1)?.activeID == before)
    }

    @Test func everyShortcutHasItsOwnKeyCombination() {
        let combos = HotKeys.bindings.map { "\($0.1)-\($0.2)" }
        #expect(Set(combos).count == combos.count)
        #expect(HotKeys.bindings.count == HotKeys.Action.allCases.count)
    }
}
