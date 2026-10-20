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
        DropTargetResolver.resolve(cursor: p, windows: windows, dragged: dragged.id, ownPID: ownPID, isEligible: { eligible.contains($0) })
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
}
