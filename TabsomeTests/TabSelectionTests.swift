import CoreGraphics
import Testing
@testable import Tabsome

struct TabSelectionTests {
    let order: [CGWindowID] = [1, 2, 3, 4, 5]

    @Test mutating func shiftClickSelectsTheRangeFromTheAnchor() {
        var s = TabSelection(active: 2)
        let r1 = s.click(4, modifier: .shift, order: order, active: 2)
        #expect(r1)
        #expect(s.selected == [2, 3, 4])
        let again = s.click(1, modifier: .shift, order: order, active: 4) // range from the same anchor
        #expect(again)
        #expect(s.selected == [1, 2])
    }

    @Test mutating func commandClickTogglesOneTab() {
        var s = TabSelection(active: 1)
        let r2 = s.click(3, modifier: .command, order: order, active: 1)
        #expect(r2)
        #expect(s.selected == [1, 3])
        let r3 = s.click(3, modifier: .command, order: order, active: 1)
        #expect(!r3)
        #expect(s.selected == [1])
    }

    @Test mutating func theActiveTabCantBeDeselected() {
        var s = TabSelection(active: 1)
        _ = s.click(3, modifier: .command, order: order, active: 1)
        let r4 = s.click(1, modifier: .command, order: order, active: 1)
        #expect(!r4)
        #expect(s.selected.contains(1))
    }

    @Test mutating func aPlainPressKeepsTheSelectionForDraggingThenCollapses() {
        var s = TabSelection(active: 2)
        _ = s.click(4, modifier: .shift, order: order, active: 2)
        let r5 = s.click(3, modifier: .none, order: order, active: 4)
        #expect(r5)
        #expect(s.selected == [2, 3, 4]) // still selected: a drag would carry all three
        s.collapse(to: 3)
        #expect(s.selected == [3])
        let r6 = s.click(5, modifier: .none, order: order, active: 3)
        #expect(r6)
        #expect(s.selected == [5]) // pressing an unselected tab selects only it
    }

    @Test mutating func pruneKeepsOnlyCurrentTabsAndTheActiveOne() {
        var s = TabSelection(active: 1)
        _ = s.click(5, modifier: .shift, order: order, active: 1)
        s.prune(to: [1, 2, 3], active: 2)
        #expect(s.selected == [1, 2, 3])
        #expect(s.ordered([3, 1, 2]) == [3, 1, 2])
    }
}

struct LeftLayoutTests {
    @Test func iconsStackDownTheColumnWithPlusBelow() {
        let l = StripLayout.left(height: 600, count: 3, active: 0, showsPlus: true)
        #expect(l.vertical)
        #expect(l.frames.map(\.minY) == [8, 44, 80])
        #expect(l.frames.allSatisfy { $0.width == Metrics.leftStripWidth })
        #expect(l.plusButton?.minY == 116)
        #expect(l.insertIndex(at: 50, count: 3) == 1)
        #expect(l.insertIndex(at: 70, count: 3) == 2)
        #expect(l.markerPosition(for: 3) == 116)
        #expect(l.tab(at: 90) == 2)
    }

    @Test func tooManyOverflowIntoAMenuKeepingTheActiveTab() {
        let l = StripLayout.left(height: 300, count: 20, active: 19, showsPlus: true)
        #expect(!l.overflow.isEmpty)
        #expect(l.visible.contains(19))
        #expect(l.overflowButton != nil)
        #expect((l.plusButton?.maxY ?? 0) <= 300)
    }
}
