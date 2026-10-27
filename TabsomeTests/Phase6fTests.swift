import CoreGraphics
import Testing
@testable import Tabsome

/// Browser parity (PLAN.md §7 Phase 6f): torn-out tabs dropped back on their own strip.
struct ReturnToOwnStripTests {
    func group(_ members: [CGWindowID]) -> TabGroup {
        TabGroup(members: members, active: members[0], content: .zero)
    }

    @Test func oneTabGoesInAtTheMarker() {
        var g = group([1, 2, 3, 4])
        g.move([2], to: 4) // the marker after the last tab, counted with 2 still in place
        #expect(g.members == [1, 3, 4, 2])
        g.move([2], to: 0)
        #expect(g.members == [2, 1, 3, 4])
    }

    @Test func droppingWhereItCameFromChangesNothing() {
        var g = group([1, 2, 3, 4])
        g.move([2], to: 1)
        #expect(g.members == [1, 2, 3, 4])
        g.move([2], to: 2)
        #expect(g.members == [1, 2, 3, 4])
    }

    @Test func aSelectionKeepsItsOrder() {
        var g = group([1, 2, 3, 4, 5])
        g.move([4, 2], to: 5)
        #expect(g.members == [1, 3, 5, 2, 4])
        g.move([5, 1], to: 0)
        #expect(g.members == [1, 5, 3, 2, 4])
    }
}
