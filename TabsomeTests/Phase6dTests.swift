import CoreGraphics
import Testing
@testable import Tabsome

/// The first-time hint and VoiceOver values (PLAN.md §7 Phase 6d).
struct FirstTimeHintTests {
    let hovering = DwellStateMachine.State.hovering(target: 1, anchor: .zero, since: 0)

    @Test func saysPauseWhileHoveringAndLetGoOnceArmed() {
        #expect(FirstTimeHint.text(for: hovering, groupsMade: 0) == "Pause to make tabs")
        #expect(FirstTimeHint.text(for: .armed(target: 1), groupsMade: 1) == "Let go to make tabs")
    }

    @Test func staysQuietOutsideAWindowsMiddleAndOverStrips() {
        #expect(FirstTimeHint.text(for: .idle, groupsMade: 0) == nil)
        #expect(FirstTimeHint.text(for: .armedOnStrip(target: 1, index: 0), groupsMade: 0) == nil)
    }

    @Test func stopsAfterTwoGroups() {
        #expect(FirstTimeHint.text(for: hovering, groupsMade: 2) == nil)
        #expect(FirstTimeHint.text(for: .armed(target: 1), groupsMade: 5) == nil)
    }
}

struct TabAccessibilityTests {
    @Test func valueIsThePositionThenTheBadge() {
        #expect(TabAccessibility.value(index: 1, count: 5, badge: nil) == "2 of 5")
        #expect(TabAccessibility.value(index: 0, count: 2, badge: "3") == "1 of 2, badge 3")
    }
}
