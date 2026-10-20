import CoreGraphics

/// Finds what a drag would tab into (PLAN.md §5.2). Pure: the window list, the strip lookup, and
/// the eligibility check come in as arguments, so it's tested without a window server.
nonisolated enum DropTargetResolver {
    struct Target: Equatable {
        let id: CGWindowID
        /// Window-server bounds at resolve time (global, top-left origin).
        let frame: CGRect
        /// Whether the cursor is in the target's middle zone (only then can it arm).
        let inMiddle: Bool
    }

    /// A group's tab strip under the cursor: the group's active window and where a drop would land.
    struct StripHit: Equatable {
        let target: CGWindowID
        let index: Int
    }

    enum Resolved: Equatable {
        case window(Target)
        case strip(StripHit)

        var dwellTarget: DwellTarget? {
            switch self {
            case .window(let t): t.inMiddle ? .middle(t.id) : nil
            case .strip(let s): .strip(s.target, index: s.index)
            }
        }
    }

    /// - Parameters:
    ///   - windows: on-screen windows, front to back.
    ///   - dragged: the window being dragged (never its own target).
    ///   - ownPID: Tabsome's process. Its tab strips can be targets (via `strip`); its other
    ///     overlays (highlight, proxies) never are.
    ///   - strip: for one of Tabsome's windows, the strip hit at the cursor, or nil when it isn't
    ///     a strip that can take the drop (the dragged tab's own strip, or a full group).
    ///   - isEligible: standard, not excluded, not minimized, room in its group (S6, §1).
    ///     Ineligible windows under the cursor (a small popup) are skipped, so the one behind counts.
    static func resolve(cursor: CGPoint, windows: [ScreenWindow], dragged: CGWindowID, ownPID: pid_t,
                        strip: (ScreenWindow) -> StripHit? = { _ in nil },
                        isEligible: (CGWindowID) -> Bool, inset: CGFloat = DropZone.defaultInset) -> Resolved? {
        for w in windows where w.layer == 0 && w.bounds.contains(cursor) {
            if w.id == dragged { continue }
            if w.pid == ownPID {
                if let hit = strip(w) { return .strip(hit) }
                continue
            }
            guard isEligible(w.id) else { continue }
            return .window(Target(id: w.id, frame: w.bounds, inMiddle: DropZone.contains(cursor, frame: w.bounds, inset: inset)))
        }
        return nil
    }
}
