import CoreGraphics
import Testing
@testable import Tabsome

struct DwellStateMachineTests {
    var m = DwellStateMachine()
    let p = CGPoint(x: 500, y: 400)

    @Test mutating func enteringAZoneStartsTheDwell() {
        #expect(m.update(cursor: p, time: 10, target: 7) == [.scheduleTick(at: 10.45)])
        #expect(m.state == .hovering(target: 7, anchor: p, since: 10))
    }

    @Test mutating func holdingStillArmsOnTheTick() {
        _ = m.update(cursor: p, time: 10, target: 7)
        #expect(m.tick(time: 10.45) == [.showHighlight(target: 7)])
        #expect(m.state == .armed(target: 7))
    }

    @Test mutating func anEarlyTickReschedules() {
        _ = m.update(cursor: p, time: 10, target: 7)
        #expect(m.tick(time: 10.2) == [.scheduleTick(at: 10.45)])
        #expect(m.state == .hovering(target: 7, anchor: p, since: 10))
    }

    @Test mutating func jitterUnderSixPointsDoesNotRestart() {
        _ = m.update(cursor: p, time: 10, target: 7)
        #expect(m.update(cursor: CGPoint(x: 503, y: 404), time: 10.3, target: 7) == []) // 5 pt
        #expect(m.update(cursor: CGPoint(x: 503, y: 404), time: 10.5, target: 7) == [.showHighlight(target: 7)])
    }

    @Test mutating func movingRestartsThePause() {
        _ = m.update(cursor: p, time: 10, target: 7)
        let moved = CGPoint(x: 510, y: 400)
        #expect(m.update(cursor: moved, time: 10.4, target: 7) == [.scheduleTick(at: 10.85)])
        #expect(m.tick(time: 10.45) == [.scheduleTick(at: 10.85)])
        #expect(m.tick(time: 10.85) == [.showHighlight(target: 7)])
    }

    @Test mutating func aNewTargetRestarts() {
        _ = m.update(cursor: p, time: 10, target: 7)
        #expect(m.update(cursor: p, time: 10.3, target: 8) == [.scheduleTick(at: 10.75)])
        #expect(m.state == .hovering(target: 8, anchor: p, since: 10.3))
    }

    @Test mutating func leavingTheZoneBeforeArmingDoesNothingVisible() {
        _ = m.update(cursor: p, time: 10, target: 7)
        #expect(m.update(cursor: p, time: 10.2, target: nil) == [])
        #expect(m.state == .idle)
        #expect(m.tick(time: 10.45) == [])
    }

    @Test mutating func leavingWhileArmedHidesTheHighlight() {
        _ = m.update(cursor: p, time: 10, target: 7)
        _ = m.tick(time: 10.45)
        #expect(m.update(cursor: CGPoint(x: 900, y: 400), time: 11, target: nil) == [.hideHighlight])
        #expect(m.state == .idle)
    }

    @Test mutating func movingWithinTheZoneStaysArmed() {
        _ = m.update(cursor: p, time: 10, target: 7)
        _ = m.tick(time: 10.45)
        #expect(m.update(cursor: CGPoint(x: 560, y: 430), time: 11, target: 7) == [])
        #expect(m.state == .armed(target: 7))
    }

    @Test mutating func armedOntoAnotherTargetHidesAndRestarts() {
        _ = m.update(cursor: p, time: 10, target: 7)
        _ = m.tick(time: 10.45)
        #expect(m.update(cursor: p, time: 11, target: 8) == [.hideHighlight, .scheduleTick(at: 11.45)])
    }

    @Test mutating func mouseUpWhileArmedDrops() {
        _ = m.update(cursor: p, time: 10, target: 7)
        _ = m.tick(time: 10.45)
        #expect(m.mouseUp() == [.hideHighlight, .drop(target: 7)])
        #expect(m.state == .idle)
    }

    @Test mutating func mouseUpAnyOtherTimeDoesNothing() {
        #expect(m.mouseUp() == [])
        _ = m.update(cursor: p, time: 10, target: 7)
        #expect(m.mouseUp() == [])
        #expect(m.state == .idle)
    }

    @Test mutating func cancelHidesOnlyWhenArmed() {
        _ = m.update(cursor: p, time: 10, target: 7)
        #expect(m.cancel() == [])
        _ = m.update(cursor: p, time: 20, target: 7)
        _ = m.tick(time: 20.45)
        #expect(m.cancel() == [.hideHighlight])
    }

    @Test func dwellIsConfigurable() {
        var fast = DwellStateMachine(config: .init(dwell: 0.2, jitter: 6))
        #expect(fast.update(cursor: p, time: 0, target: 1) == [.scheduleTick(at: 0.2)])
        #expect(fast.tick(time: 0.2) == [.showHighlight(target: 1)])
    }
}
