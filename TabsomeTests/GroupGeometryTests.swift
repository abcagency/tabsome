import CoreGraphics
import Testing
@testable import Tabsome

struct GroupGeometryTests {
    let requested = CGRect(x: 100, y: 132, width: 800, height: 568)

    @Test func adoptsTheStrictestNearbyFrame() {
        // Terminal rounds to its grid: a few points smaller.
        let landed = [requested, CGRect(x: 100, y: 132, width: 798, height: 563)]
        #expect(GroupGeometry.reconcile(requested: requested, landed: landed) == CGRect(x: 100, y: 132, width: 798, height: 563))
    }

    @Test func growsToAMemberThatCantGetSmallEnough() {
        // Notes' minimum height is bigger than the group: the group takes it.
        let landed = [requested, CGRect(x: 100, y: 132, width: 798, height: 700)]
        #expect(GroupGeometry.reconcile(requested: requested, landed: landed) == CGRect(x: 100, y: 132, width: 800, height: 700))
    }

    @Test func aMemberThatCantGetBigEnoughDoesntShrinkTheGroup() {
        // A fixed-size window far smaller than the group: concealment's job, not the group's.
        let landed = [requested, CGRect(x: 100, y: 132, width: 500, height: 400)]
        #expect(GroupGeometry.reconcile(requested: requested, landed: landed) == requested)
    }

    @Test func aGrownGroupStaysOnScreen() {
        let v = CGRect(x: 0, y: 25, width: 1600, height: 1000)
        #expect(GroupGeometry.keepOnScreen(CGRect(x: 100, y: 600, width: 800, height: 700), visibleFrame: v) == CGRect(x: 100, y: 325, width: 800, height: 700))
        #expect(GroupGeometry.keepOnScreen(CGRect(x: 100, y: 100, width: 800, height: 600), visibleFrame: v) == CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(GroupGeometry.keepOnScreen(CGRect(x: 100, y: 100, width: 2000, height: 600), visibleFrame: v).minX == 0)
    }

    @Test func fillThenReturn() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let outer = CGRect(x: 100, y: 100, width: 800, height: 600)
        let filled = GroupGeometry.fillToggle(outer: outer, previous: nil, visibleFrame: visible)
        #expect(filled.outer == visible)
        #expect(filled.previous == outer)
        let back = GroupGeometry.fillToggle(outer: filled.outer, previous: filled.previous, visibleFrame: visible)
        #expect(back.outer == outer)
        #expect(back.previous == nil)
    }

    @Test func cascadeKeepsTheActiveTabInPlaceAndStepsTheOthers() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let outer = CGRect(x: 100, y: 100, width: 800, height: 600)
        let plan = GroupGeometry.cascade(outer: outer, activeFirst: [7, 8, 9], visibleFrame: visible)
        #expect(plan[7] == outer)
        #expect(plan[8] == outer.offsetBy(dx: 22, dy: 22))
        #expect(plan[9] == outer.offsetBy(dx: 44, dy: 44))
    }

    @Test func cascadeWrapsInsideTheUsableArea() {
        let visible = CGRect(x: 0, y: 25, width: 1000, height: 700)
        let outer = CGRect(x: 150, y: 70, width: 800, height: 600) // only one step fits
        let plan = GroupGeometry.cascade(outer: outer, activeFirst: [1, 2, 3], visibleFrame: visible)
        for frame in plan.values {
            #expect(visible.contains(frame) || frame == outer)
        }
        #expect(plan[3] != plan[2])
    }

    @Test func expectedFramesMatchLooselyAndExpire() {
        var e = ExpectedFrames()
        e.expect(requested, for: 5, now: 10)
        #expect(e.isExpected(requested.insetBy(dx: 2, dy: 2), for: 5, now: 10.5))
        #expect(!e.isExpected(requested.offsetBy(dx: 50, dy: 0), for: 5, now: 10.5))
        #expect(!e.isExpected(requested, for: 5, now: 11.5))
        #expect(!e.isExpected(requested, for: 6, now: 10.5))
    }
}

struct ParkingTests {
    let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let size = CGSize(width: 800, height: 600)

    @Test func aloneTheWindowGoesPastTheBottomRightCorner() {
        #expect(GroupGeometry.parkingOrigin(screen: main, size: size) == CGPoint(x: 2559, y: 1439))
    }

    @Test func avoidsSpillingOntoADisplayToTheRight() {
        let right = CGRect(x: 2560, y: 0, width: 1920, height: 2400) // tall enough to catch bottom-right
        let origin = GroupGeometry.parkingOrigin(screen: main, size: size, otherScreens: [right])
        #expect(CGRect(origin: origin, size: size).intersection(right).isNull)
        #expect(origin == CGPoint(x: 1 - 800, y: 1439)) // bottom-left instead
    }

    @Test func avoidsDisplaysToTheRightAndBelow() {
        let right = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        let below = CGRect(x: -500, y: 1440, width: 3000, height: 1200)
        let origin = GroupGeometry.parkingOrigin(screen: main, size: size, otherScreens: [right, below])
        let r = CGRect(origin: origin, size: size)
        #expect(r.intersection(right).isNull && r.intersection(below).isNull)
    }
}
