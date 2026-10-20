import CoreGraphics
import Testing
@testable import Tabsome

struct StripLayoutTests {
    let outer = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test func topStripTakesThirtyTwoPointsOffTheTop() {
        let f = StripLayout.frames(outer: outer, placement: .top)
        #expect(f.strip == CGRect(x: 100, y: 100, width: 800, height: 32))
        #expect(f.content == CGRect(x: 100, y: 132, width: 800, height: 568))
    }

    @Test func leftStripTakesFortyPointsOffTheLeft() {
        let f = StripLayout.frames(outer: outer, placement: .left)
        #expect(f.strip == CGRect(x: 100, y: 100, width: 40, height: 600))
        #expect(f.content == CGRect(x: 140, y: 100, width: 760, height: 600))
    }

    @Test(arguments: TabPlacement.allCases)
    func outerAndFramesRoundTrip(placement: TabPlacement) {
        let content = StripLayout.frames(outer: outer, placement: placement).content
        #expect(StripLayout.outer(content: content, placement: placement) == outer)
    }

    @Test func tabsShareTheWidthAfterTheButtons() {
        let tabs = StripLayout.tabFrames(stripWidth: 800, count: 3)
        #expect(tabs.count == 3)
        #expect(tabs[0].minX == StripLayout.tabsLeadingInset)
        #expect(abs(tabs[2].maxX - (800 - StripLayout.tabsTrailingInset)) < 0.001)
        #expect(Set(tabs.map { ($0.width * 1000).rounded() }).count == 1)
        #expect(StripLayout.tabFrames(stripWidth: 800, count: 0).isEmpty)
    }
}

struct StripTopLayoutTests {
    let width: CGFloat = 1000
    var available: CGFloat { width - StripLayout.tabsLeadingInset - StripLayout.tabsTrailingInset - StripLayout.buttonWidth }

    @Test func fewTabsShowFullWidthWithPlus() {
        let l = StripLayout.top(width: width, count: 3, active: 0, showsPlus: true)
        #expect(l.style == .full)
        #expect(l.visible == [0, 1, 2])
        #expect(l.overflow.isEmpty)
        #expect(l.plusButton?.minX == l.frames.last?.maxX)
    }

    @Test func belowNinetyPointsTabsGoIconOnly() {
        let count = Int(available / 80) // ~80 pt each
        let l = StripLayout.top(width: width, count: count, active: 0, showsPlus: true)
        #expect(l.style == .iconOnly)
        #expect(l.overflow.isEmpty)
    }

    @Test func tooManyOverflowButTheActiveTabStaysVisible() {
        let l = StripLayout.top(width: width, count: 50, active: 49, showsPlus: true)
        #expect(l.style == .iconOnly)
        #expect(!l.overflow.isEmpty)
        #expect(l.visible.contains(49))
        #expect(l.visible.count + l.overflow.count == 50)
        #expect(Set(l.visible).isDisjoint(with: l.overflow))
        #expect(l.overflowButton != nil)
        #expect((l.plusButton?.maxX ?? 0) <= width)
    }

    @Test func noPlusWhenFull() {
        #expect(StripLayout.top(width: width, count: 4, active: 0, showsPlus: false).plusButton == nil)
    }

    @Test func insertIndexFollowsTabMidpoints() {
        let l = StripLayout.top(width: width, count: 3, active: 0, showsPlus: false)
        #expect(l.insertIndex(at: l.frames[0].minX + 1, count: 3) == 0)
        #expect(l.insertIndex(at: l.frames[0].maxX - 1, count: 3) == 1)
        #expect(l.insertIndex(at: l.frames[2].maxX - 1, count: 3) == 3)
        #expect(l.markerX(for: 1) == l.frames[1].minX)
        #expect(l.markerX(for: 3) == l.frames[2].maxX)
        #expect(l.tab(at: l.frames[1].midX) == 1)
    }

    @Test func frozenWidthHoldsTabsStill() {
        let l = StripLayout.top(width: width, count: 2, active: 0, showsPlus: true, frozenWidth: 150)
        #expect(l.frames.map(\.width) == [150, 150])
        #expect(l.frames[0].minX == StripLayout.tabsLeadingInset)
    }
}
