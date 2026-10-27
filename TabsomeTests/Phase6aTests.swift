import CoreGraphics
import Testing
@testable import Tabsome

/// Settings › Tabs strip options and Settings › General drag settings (PLAN.md §7 Phase 6a).
/// Every call passes its options explicitly, so nothing here touches `StripLayout.options`.
struct StripOptionsTests {
    let outer = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test func mediumIsTheMeasuredSize() {
        #expect(StripLayout.thickness(.top, size: .medium) == Metrics.topStripHeight)
        #expect(StripLayout.thickness(.left, size: .medium) == Metrics.leftStripWidth)
        #expect(StripLayout.thickness(.leftNamed, size: .medium) == Metrics.leftNamedStripWidth)
        #expect(StripLayout.leftIconSize(.medium) == 28)
        #expect(StripLayout.leftSlotHeight(.medium) == 36)
    }

    @Test(arguments: TabPlacement.allCases)
    func sizesGrowFromSmallToLarge(placement: TabPlacement) {
        let t = StripSize.allCases.map { StripLayout.thickness(placement, size: $0) }
        #expect(t == t.sorted() && Set(t).count == 3)
    }

    @Test(arguments: TabPlacement.allCases, StripSize.allCases)
    func framesRoundTripAtEverySize(placement: TabPlacement, size: StripSize) {
        let f = StripLayout.frames(outer: outer, placement: placement, size: size)
        let t = StripLayout.thickness(placement, size: size)
        #expect((placement == .top ? f.strip.height : f.strip.width) == t)
        #expect(StripLayout.outer(content: f.content, placement: placement, size: size) == outer)
    }

    @Test func largeTopStripIsThirtyEightPointsTall() {
        var o = StripOptions()
        o.size = .large
        let layout = StripLayout.top(width: 800, count: 2, active: 0, showsPlus: true, options: o)
        #expect(layout.frames.allSatisfy { $0.height == 38 })
        #expect(layout.plusButton?.height == 38)
    }

    @Test func minTabWidthDecidesWhenNamesGiveWayToIcons() {
        // 800 pt strip: about 640 pt for tabs once the buttons and "+" are out, so 5 tabs get ~128 pt each.
        var o = StripOptions()
        o.minTabWidth = 90
        #expect(StripLayout.top(width: 800, count: 5, active: 0, showsPlus: true, options: o).style == .full)
        o.minTabWidth = 150
        #expect(StripLayout.top(width: 800, count: 5, active: 0, showsPlus: true, options: o).style == .iconOnly)
        o.minTabWidth = 60
        #expect(StripLayout.top(width: 800, count: 9, active: 0, showsPlus: true, options: o).style == .full)
    }

    @Test func smallLeftColumnFitsMoreIconsBeforeOverflowing() {
        let medium = StripLayout.left(height: 400, count: 20, active: 0, showsPlus: true, size: .medium)
        let small = StripLayout.left(height: 400, count: 20, active: 0, showsPlus: true, size: .small)
        #expect(small.visible.count > medium.visible.count)
        #expect(small.frames.allSatisfy { $0.width == 34 && $0.height == 32 })
    }
}

struct MiddleZoneSettingTests {
    let target = ScreenWindow(id: 1, pid: 60, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))

    private func inMiddle(_ p: CGPoint, inset: CGFloat) -> Bool? {
        guard case .window(let t) = DropTargetResolver.resolve(cursor: p, windows: [target], dragged: 99, ownPID: 1,
                                                                isEligible: { _ in true }, inset: inset) else { return nil }
        return t.inMiddle
    }

    @Test func aLargerMiddleReachesFurtherOut() {
        let p = CGPoint(x: 200, y: 500)
        #expect(inMiddle(p, inset: 0.25) == false) // the default central 50%
        #expect(inMiddle(p, inset: 0.15) == true)  // a 70% middle
    }

    @Test func aSmallerMiddleStaysCentral() {
        let p = CGPoint(x: 320, y: 500)
        #expect(inMiddle(p, inset: 0.25) == true)
        #expect(inMiddle(p, inset: 0.35) == false) // a 30% middle
    }
}
