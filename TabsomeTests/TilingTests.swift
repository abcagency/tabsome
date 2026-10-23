import CoreGraphics
import Testing
@testable import Tabsome

struct TileDetectionTests {
    let v = CGRect(x: 0, y: 25, width: 1600, height: 1000)

    @Test(arguments: [
        CGRect(x: 0, y: 25, width: 1600, height: 1000),     // Fill
        CGRect(x: 0, y: 25, width: 800, height: 1000),      // Left
        CGRect(x: 800, y: 25, width: 800, height: 1000),    // Right
        CGRect(x: 0, y: 25, width: 1600, height: 500),      // Top
        CGRect(x: 0, y: 525, width: 1600, height: 500),     // Bottom
        CGRect(x: 800, y: 525, width: 800, height: 500),    // Bottom Right
        CGRect(x: 8, y: 33, width: 788, height: 488),       // Top Left, with tiled-window margins
    ])
    func tilesAreRecognized(frame: CGRect) {
        #expect(GroupGeometry.isTile(frame, visibleFrame: v))
    }

    @Test func ordinaryFramesAreNotTiles() {
        #expect(!GroupGeometry.isTile(CGRect(x: 200, y: 150, width: 900, height: 600), visibleFrame: v))
        #expect(!GroupGeometry.isTile(CGRect(x: 0, y: 25, width: 1100, height: 1000), visibleFrame: v))
    }

    @Test(arguments: Tabsome.TabPlacement.allCases)
    func aGroupsOwnContentFrameIsNeverATile(placement: Tabsome.TabPlacement) {
        for outer in [v, CGRect(x: 0, y: 25, width: 800, height: 1000), CGRect(x: 800, y: 525, width: 800, height: 500)] {
            let content = StripLayout.frames(outer: outer, placement: placement).content
            #expect(!GroupGeometry.isTile(content, visibleFrame: v))
        }
    }
}

@MainActor
struct RefitTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager
    let usable = CGRect(x: 0, y: 25, width: 1600, height: 1000)

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.settleDuration = 0
        manager.windowBounds = { _ in nil }
        manager.usableArea = { [usable] _ in usable }
        for (pid, name) in [(101, "Safari"), (202, "Finder")] as [(pid_t, String)] {
            registry.track(.init(pid: pid, name: name, bundleID: "t.\(name)"))
            system.send(.appWindows(pid, [snapshot(CGWindowID(pid / 101), pid: pid, frame: CGRect(x: 100, y: 100, width: 800, height: 600))]))
        }
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
    }

    @Test func aTiledActiveWindowRefitsTheWholeGroupToTheTile() throws {
        let g = try #require(manager.group(containing: 1))
        let left = CGRect(x: 0, y: 25, width: 800, height: 1000)
        system.send(.windowUpdated(snapshot(g.activeID, pid: g.activeID == 1 ? 101 : 202, frame: left)))
        system.clearCommands()
        #expect(manager.refitIfTiled(g.id))
        let after = try #require(manager.group(containing: 1))
        #expect(after.outer == left)
        #expect(after.content == StripLayout.frames(outer: left, placement: after.placement).content)
        let moved = Set(system.commands.compactMap { c, w -> CGWindowID? in if case .setFrame(let f) = c, f == after.content { w } else { nil } })
        #expect(moved == [1, 2])
    }

    @Test func anOrdinaryMoveIsNotARefit() throws {
        let g = try #require(manager.group(containing: 1))
        let moved = g.content.offsetBy(dx: 40, dy: 30)
        system.send(.windowUpdated(snapshot(g.activeID, pid: g.activeID == 1 ? 101 : 202, frame: moved)))
        #expect(!manager.refitIfTiled(g.id))
        #expect(try #require(manager.group(containing: 1)).content == moved)
    }
}
