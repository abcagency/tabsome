import SwiftUI
import Testing
@testable import Tabsome

struct WindowButtonColorsTests {
    typealias C = WindowButtonColors

    @Test func graphiteMakesAllThreeTheSameGrey() {
        for dark in [false, true] {
            let fills = [C.Kind.close, .minimize, .zoom].map { C.style($0, active: true, graphite: true, dark: dark).fill }
            #expect(Set(fills).count == 1)
        }
        #expect(C.style(.close, active: true, graphite: true, dark: true).fill == Color(red: 0x93 / 255, green: 0x94 / 255, blue: 0x95 / 255))
    }

    @Test func multicolorKeepsRedYellowGreen() {
        let fills = [C.Kind.close, .minimize, .zoom].map { C.style($0, active: true, graphite: false, dark: false).fill }
        #expect(Set(fills).count == 3)
    }

    @Test func unfocusedIsTheSameGreyWhateverTheAccent() {
        for dark in [false, true] {
            #expect(C.style(.close, active: false, graphite: true, dark: dark).fill == C.style(.zoom, active: false, graphite: false, dark: dark).fill)
        }
        #expect(C.style(.close, active: false, graphite: false, dark: false).fill != C.style(.close, active: false, graphite: false, dark: true).fill)
    }
}
