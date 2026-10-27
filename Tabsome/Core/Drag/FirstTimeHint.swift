import Foundation

/// The first-time hint (PLAN.md §7 Phase 6): while someone who hasn't made tabs yet drags a
/// window over another window's middle, a label by the cursor says what to do. Pure, so the
/// rules are tested without a drag.
nonisolated enum FirstTimeHint {
    /// After this many groups made by dragging, the hint never shows again.
    static let groupsToLearn = 2
    static let groupsMadeKey = "hintGroupsMade"

    static let pause = "Pause to make tabs"
    static let letGo = "Let go to make tabs"

    /// What the label says for this point in the dwell, or nil for no label. Over a tab strip
    /// there's no pause to explain, and its insertion marker already shows where the tab goes.
    static func text(for state: DwellStateMachine.State, groupsMade: Int) -> String? {
        guard groupsMade < groupsToLearn else { return nil }
        switch state {
        case .hovering: return pause
        case .armed: return letGo
        case .idle, .armedOnStrip: return nil
        }
    }
}
