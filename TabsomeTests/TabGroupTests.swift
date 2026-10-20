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

struct TabGroupPhase4Tests {
    let content = CGRect(x: 0, y: 32, width: 800, height: 568)

    @Test func insertsAtAPositionAndReorders() {
        var g = TabGroup(members: [1, 2, 3], active: 1, content: content)
        let inserted = g.insert([9, 8], at: 1)
        #expect(inserted)
        #expect(g.members == [1, 9, 8, 2, 3])
        g.move(3, to: 0)
        #expect(g.members == [3, 1, 9, 8, 2])
        g.move(3, to: 99)
        #expect(g.members == [1, 9, 8, 2, 3])
    }

    @Test func theQuietLimitIsFiftyTabs() {
        var g = TabGroup(members: Array(1...49), active: 1, content: content)
        #expect(g.canAccept(1))
        #expect(!g.canAccept(2))
        let added = g.add(100)
        let overLimit = g.add(101)
        let overLimitPair = g.insert([102, 103])
        #expect(added)
        #expect(!overLimit)
        #expect(!overLimitPair)
        #expect(g.count == 50)
    }

    @Test func othersAndToTheRight() {
        let g = TabGroup(members: [1, 2, 3, 4], active: 2, content: content)
        #expect(g.others(than: 2) == [1, 3, 4])
        #expect(g.toTheRight(of: 2) == [3, 4])
        #expect(g.toTheRight(of: 4).isEmpty)
    }
}
