import CoreGraphics
import Testing
@testable import Tabsome

struct TabGroupTests {
    let content = CGRect(x: 100, y: 132, width: 800, height: 568)

    func group(_ members: [CGWindowID], active: CGWindowID) -> TabGroup {
        TabGroup(members: members, active: active, content: content)
    }

    @Test func newTabsGoAtTheEnd() {
        var g = group([1, 2], active: 2)
        g.add(3)
        #expect(g.members == [1, 2, 3])
        g.add(2)
        #expect(g.members == [1, 2, 3])
    }

    @Test func closingTheActiveTabActivatesTheOneToItsRight() {
        var g = group([1, 2, 3], active: 2)
        #expect(g.remove(2) == 3)
        #expect(g.activeID == 3)
    }

    @Test func closingTheLastActiveTabActivatesTheOneToItsLeft() {
        var g = group([1, 2, 3], active: 3)
        #expect(g.remove(3) == 2)
    }

    @Test func closingAnInactiveTabKeepsTheActiveOne() {
        var g = group([1, 2, 3], active: 1)
        #expect(g.remove(3) == nil)
        #expect(g.activeID == 1)
    }

    @Test func aGroupOfOneDissolves() {
        var g = group([1, 2], active: 1)
        #expect(!g.shouldDissolve)
        g.remove(2)
        #expect(g.shouldDissolve)
    }

    @Test func outerIncludesTheStrip() {
        #expect(group([1, 2], active: 1).outer == CGRect(x: 100, y: 100, width: 800, height: 600))
    }
}
