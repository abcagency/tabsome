import CoreGraphics
import Testing
@testable import Tabsome

struct DragClassifierTests {
    let down = CGRect(x: 300, y: 260, width: 760, height: 420)

    @Test func moveWithSameSizeIsADrag() {
        #expect(DragClassifier.classify(downFrame: down, current: down.offsetBy(dx: 40, dy: 12)) == .drag)
    }

    @Test func resizeFromTheTopLeftIsNotADrag() {
        let r = CGRect(x: 260, y: 230, width: 800, height: 450)
        #expect(DragClassifier.classify(downFrame: down, current: r) == .resize)
    }

    @Test func noChangeIsNothing() {
        #expect(DragClassifier.classify(downFrame: down, current: down) == .none)
    }
}
