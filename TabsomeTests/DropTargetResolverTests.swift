import CoreGraphics
import Testing
@testable import Tabsome

struct DropTargetResolverTests {
    let ownPID: pid_t = 1
    // Front to back.
    let dragged = ScreenWindow(id: 10, pid: 50, layer: 0, bounds: CGRect(x: 380, y: 280, width: 300, height: 200))
    let overlay = ScreenWindow(id: 11, pid: 1, layer: 0, bounds: CGRect(x: 0, y: 0, width: 2000, height: 2000))
    let popup = ScreenWindow(id: 12, pid: 60, layer: 0, bounds: CGRect(x: 480, y: 360, width: 60, height: 30))
    let menu = ScreenWindow(id: 13, pid: 70, layer: 25, bounds: CGRect(x: 0, y: 0, width: 2000, height: 30))
    let target = ScreenWindow(id: 20, pid: 60, layer: 0, bounds: CGRect(x: 200, y: 200, width: 600, height: 400))
    let behind = ScreenWindow(id: 30, pid: 80, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1500, height: 1000))

    var windows: [ScreenWindow] { [menu, dragged, overlay, popup, target, behind] }

    func resolve(_ p: CGPoint, eligible: Set<CGWindowID> = [20, 30]) -> DropTargetResolver.Target? {
        guard case .window(let t) = DropTargetResolver.resolve(cursor: p, windows: windows, dragged: dragged.id, ownPID: ownPID,
                                                                 isEligible: { eligible.contains($0) }) else { return nil }
        return t
    }

    @Test func skipsTheDraggedWindowOverlaysAndIneligiblePopups() {
        let t = resolve(CGPoint(x: 500, y: 370))
        #expect(t == .init(id: 20, frame: target.bounds, inMiddle: true))
    }

    @Test func reportsWhenTheCursorIsOutsideTheMiddle() {
        let t = resolve(CGPoint(x: 220, y: 220))
        #expect(t?.id == 20)
        #expect(t?.inMiddle == false)
    }

    @Test func ignoresNonNormalLayers() {
        // y 10 is inside the menu-bar-layer window but also inside `behind`.
        #expect(resolve(CGPoint(x: 100, y: 10))?.id == 30)
    }

    @Test func nothingEligibleMeansNoTarget() {
        #expect(resolve(CGPoint(x: 500, y: 370), eligible: []) == nil)
        #expect(resolve(CGPoint(x: 1800, y: 1800)) == nil)
    }

    @Test func aStripUnderTheCursorWinsWithItsInsertIndex() {
        let strip = ScreenWindow(id: 40, pid: ownPID, layer: 0, bounds: CGRect(x: 200, y: 168, width: 600, height: 32))
        let list = [dragged, strip, target]
        let hit = DropTargetResolver.resolve(cursor: CGPoint(x: 400, y: 180), windows: list, dragged: dragged.id, ownPID: ownPID,
                                             strip: { $0.id == 40 ? .init(target: 20, index: 1) : nil }, isEligible: { _ in true })
        #expect(hit == .strip(.init(target: 20, index: 1)))
        #expect(hit?.dwellTarget == .strip(20, index: 1))
    }

    @Test func aStripThatCantTakeTheDropIsSkipped() {
        let strip = ScreenWindow(id: 40, pid: ownPID, layer: 0, bounds: CGRect(x: 200, y: 168, width: 600, height: 400))
        let hit = DropTargetResolver.resolve(cursor: CGPoint(x: 500, y: 400), windows: [strip, target], dragged: dragged.id, ownPID: ownPID,
                                             strip: { _ in nil }, isEligible: { _ in true })
        #expect(hit == .window(.init(id: 20, frame: target.bounds, inMiddle: true)))
    }
}
