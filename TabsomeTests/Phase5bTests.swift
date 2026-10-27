import CoreGraphics
import Testing
@testable import Tabsome

struct ConcealmentGeometryTests {
    let size = CGSize(width: 800, height: 568)

    @Test func aWindowThatTookWhatItWasGivenWillAgain() {
        let last = (requested: CGSize(width: 700, height: 500), landed: CGSize(width: 697, height: 496)) // Terminal's grid
        #expect(GroupGeometry.predictedSize(for: size, last: last) == size)
        #expect(GroupGeometry.predictedSize(for: size, last: nil) == size)
    }

    @Test func aMinimumSizeHoldsUntilTheRequestIsBigEnough() {
        let last = (requested: CGSize(width: 800, height: 400), landed: CGSize(width: 800, height: 680)) // Notes
        #expect(GroupGeometry.predictedSize(for: size, last: last) == CGSize(width: 800, height: 680))
        #expect(GroupGeometry.predictedSize(for: CGSize(width: 800, height: 900), last: last) == CGSize(width: 800, height: 900))
    }

    @Test func aMaximumSizeHoldsToo() {
        let last = (requested: CGSize(width: 1200, height: 900), landed: CGSize(width: 600, height: 500)) // a fixed-size window
        #expect(GroupGeometry.predictedSize(for: size, last: last) == CGSize(width: 600, height: 500))
    }

    @Test func coveredMeansNoBiggerOnEitherSide() {
        #expect(GroupGeometry.isCovered(CGSize(width: 600, height: 500), by: size))
        #expect(GroupGeometry.isCovered(CGSize(width: 805, height: 570), by: size)) // within tolerance
        #expect(!GroupGeometry.isCovered(CGSize(width: 800, height: 680), by: size))
    }
}

struct DisplayChangeTests {
    let main = CGRect(x: 0, y: 25, width: 1600, height: 1000)
    let side = CGRect(x: 1600, y: 0, width: 1200, height: 800)

    @Test func aGroupMostlyOnAScreenStaysPut() {
        #expect(GroupGeometry.refitToScreens(outer: CGRect(x: 1300, y: 100, width: 800, height: 600), visibleFrames: [main, side]) == nil)
    }

    @Test func aGroupLeftOnARemovedDisplayMovesOntoTheFirstScreen() throws {
        let outer = CGRect(x: 1900, y: 100, width: 800, height: 600) // was on `side`, now gone
        let moved = try #require(GroupGeometry.refitToScreens(outer: outer, visibleFrames: [main]))
        #expect(main.contains(moved))
        #expect(moved.size == outer.size)
    }

    @Test func aGroupTooBigForItsNewScreenShrinks() throws {
        let outer = CGRect(x: 1700, y: 50, width: 2000, height: 1200)
        let moved = try #require(GroupGeometry.refitToScreens(outer: outer, visibleFrames: [main]))
        #expect(moved == main)
    }

    @Test func aGroupHalfOffItsScreenMovesOnToIt() throws {
        let outer = CGRect(x: 1200, y: 100, width: 1000, height: 600) // 40% on main, rest nowhere
        let moved = try #require(GroupGeometry.refitToScreens(outer: outer, visibleFrames: [main]))
        #expect(moved.maxX == main.maxX)
        #expect(moved.minY == outer.minY)
    }
}

@MainActor
struct ConcealmentTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager
    let safariFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.settleDuration = 0
        manager.windowBounds = { _ in nil }
        manager.usableArea = { _ in CGRect(x: 0, y: 25, width: 1600, height: 1000) }
        manager.onScreenWindows = { [1, 2, 3, 4] }
        registry.track(.init(pid: 101, name: "Safari", bundleID: "com.apple.Safari"))
        registry.track(.init(pid: 202, name: "Calculator", bundleID: "com.apple.calculator"))
        registry.track(.init(pid: 303, name: "Finder", bundleID: "com.apple.finder"))
        registry.track(.init(pid: 404, name: "Notes", bundleID: "com.apple.Notes"))
        system.send(.appWindows(101, [snapshot(1, pid: 101, frame: safariFrame)]))
        system.send(.appWindows(202, [snapshot(2, pid: 202, frame: CGRect(x: 900, y: 100, width: 600, height: 500))]))
        system.send(.appWindows(303, [snapshot(3, pid: 303, frame: CGRect(x: 50, y: 50, width: 300, height: 300))]))
        system.send(.appWindows(404, [snapshot(4, pid: 404, frame: CGRect(x: 900, y: 100, width: 600, height: 700))]))
        // Calculator can't get bigger than 600 × 500; Notes won't go shorter than 680 pt.
        system.landing[2] = { f in CGRect(origin: f.origin, size: CGSize(width: min(f.width, 600), height: min(f.height, 500))) }
        system.landing[4] = { f in CGRect(origin: f.origin, size: CGSize(width: f.width, height: max(f.height, 680))) }
    }

    func parks(_ id: CGWindowID) -> Int {
        system.commands.filter { if case .setPosition = $0.0 { $0.1 == id } else { false } }.count
    }

    @Test func theGroupGrowsToAMemberThatCantGetSmallEnough() throws {
        manager.merge(dragged: 4, into: 1, dropFrame: nil, snapshot: nil)
        let g = try #require(manager.group(containing: 1))
        #expect(g.content.height == 680)
        #expect(g.content.width == 800)
        #expect(system.commands.contains { $0.1 == 1 && $0.0 == .setFrame(g.content) }) // Safari grew with it
        manager.activate(1)
        #expect(manager.misfitParked.isEmpty) // nothing to hide: they're the same size now
    }

    @Test func aGrownGroupStaysOnScreen() throws {
        system.send(.windowUpdated(snapshot(1, pid: 101, frame: CGRect(x: 100, y: 500, width: 800, height: 500))))
        manager.merge(dragged: 4, into: 1, dropFrame: nil, snapshot: nil)
        let g = try #require(manager.group(containing: 1))
        #expect(g.outer.maxY <= 1025)
    }

    @Test func aBackgroundTabThatWouldShowWaitsInACorner() {
        // Calculator is active and smaller than the group: Safari would show around it.
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        #expect(manager.misfitParked == [1])
        #expect(parks(1) >= 1)
        #expect(parks(2) == 0)
    }

    @Test func itComesBackWhenActivated() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        system.clearCommands()
        manager.activate(1)
        let content = try #require(manager.group(containing: 1)).content
        #expect(manager.misfitParked.isEmpty) // Calculator now hides behind Safari
        let order = system.commands.compactMap { c, w -> String? in
            if w == 1, case .setFrame(let f) = c, f == content { return "frame" }
            if w == 1, c == .raise { return "raise" }
            return nil
        }
        #expect(order == ["frame", "raise"]) // back in place before it comes forward
        #expect(parks(2) == 0)
    }

    @Test func animationsAimForTheSizeAWindowCanTake() throws {
        // Calculator can't grow to the group's size: its proxy shouldn't either.
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        let g = try #require(manager.group(containing: 1))
        #expect(manager.landing(2, at: g.content) == CGRect(origin: g.content.origin, size: CGSize(width: 600, height: 500)))
        #expect(manager.landing(1, at: g.content) == g.content)
    }

    @Test func aTornOutTabLandsAtItsOwnSize() {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        system.clearCommands()
        manager.tearOffBegan(2, cursor: CGPoint(x: 700, y: 500))
        manager.tearOffEnded(cursor: CGPoint(x: 700, y: 500))
        let asked = system.commands.compactMap { c, w -> CGSize? in if w == 2, case .setFrame(let f) = c { f.size } else { nil } }
        #expect(asked.last == CGSize(width: 600, height: 500))
    }

    @Test func fittingTabsStayStacked() {
        manager.merge(dragged: 3, into: 1, dropFrame: nil, snapshot: nil)
        system.clearCommands()
        manager.activate(1)
        manager.activate(3)
        #expect(manager.misfitParked.isEmpty)
        #expect(parks(1) == 0 && parks(3) == 0)
    }

    @Test func theSettleCheckLeavesMisfitsAlone() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        let g = try #require(manager.group(containing: 1))
        manager.windowBounds = { $0 == 2 ? CGRect(origin: g.content.origin, size: CGSize(width: 600, height: 500)) : CGRect(x: 1599, y: 1024, width: 800, height: 568) }
        system.clearCommands()
        manager.settleCheck(g.id)
        #expect(system.commands.isEmpty)
    }

    @Test func aGroupLeftOffScreenMovesBack() throws {
        manager.merge(dragged: 3, into: 1, dropFrame: nil, snapshot: nil)
        manager.usableAreas = { [CGRect(x: 2000, y: 0, width: 1400, height: 900)] } // the display it was on is gone
        manager.revalidateScreens()
        let g = try #require(manager.group(containing: 1))
        #expect(CGRect(x: 2000, y: 0, width: 1400, height: 900).contains(g.outer))
    }
}
