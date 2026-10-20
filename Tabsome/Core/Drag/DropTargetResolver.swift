import CoreGraphics

/// Finds the window a drag would tab into (PLAN.md §5.2). Pure: the window list and the
/// eligibility check come in as arguments, so it's tested without a window server.
nonisolated enum DropTargetResolver {
    struct Target: Equatable {
        let id: CGWindowID
        /// Window-server bounds at resolve time (global, top-left origin).
        let frame: CGRect
        /// Whether the cursor is in the target's middle zone (only then can it arm).
        let inMiddle: Bool
    }

    /// - Parameters:
    ///   - windows: on-screen windows, front to back.
    ///   - dragged: the window being dragged (never its own target).
    ///   - ownPID: Tabsome's process; its overlays are never targets.
    ///   - isEligible: standard, not excluded, not minimized (S6). Ineligible windows under the
    ///     cursor (a small popup, a palette) are skipped, so the window behind can still be a target.
    static func resolve(cursor: CGPoint, windows: [ScreenWindow], dragged: CGWindowID, ownPID: pid_t,
                        isEligible: (CGWindowID) -> Bool, inset: CGFloat = DropZone.defaultInset) -> Target? {
        for w in windows where w.layer == 0 && w.bounds.contains(cursor) {
            guard w.id != dragged, w.pid != ownPID, isEligible(w.id) else { continue }
            // Phase 3: a window in the dragged window's own group is skipped here too.
            return Target(id: w.id, frame: w.bounds, inMiddle: DropZone.contains(cursor, frame: w.bounds, inset: inset))
        }
        return nil
    }
}
