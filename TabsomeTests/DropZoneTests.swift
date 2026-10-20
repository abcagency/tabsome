import CoreGraphics
import Testing
@testable import Tabsome

struct DropZoneTests {
    let frame = CGRect(x: 100, y: 200, width: 400, height: 300)

    @Test func middleIsTheCentralHalfByHalf() {
        #expect(DropZone.middle(of: frame) == CGRect(x: 200, y: 275, width: 200, height: 150))
    }

    @Test(arguments: [
        (CGPoint(x: 300, y: 350), true),   // centre
        (CGPoint(x: 200, y: 275), true),   // corner of the zone
        (CGPoint(x: 199, y: 350), false),  // just left of it
        (CGPoint(x: 300, y: 430), false),  // just below it
        (CGPoint(x: 110, y: 210), false),  // inside the window, near its edge
    ])
    func containment(point: CGPoint, inside: Bool) {
        #expect(DropZone.contains(point, frame: frame) == inside)
    }

    @Test func insetIsConfigurable() {
        #expect(DropZone.contains(CGPoint(x: 120, y: 220), frame: frame, inset: 0.0))
        #expect(!DropZone.contains(CGPoint(x: 120, y: 220), frame: frame, inset: 0.1))
    }
}
