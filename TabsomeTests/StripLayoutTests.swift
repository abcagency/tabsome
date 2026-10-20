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
