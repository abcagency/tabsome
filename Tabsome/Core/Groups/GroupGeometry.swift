import CoreGraphics

/// Pure frame math for groups.
nonisolated enum GroupGeometry {
    /// PLAN.md §5.5: some apps round the frame they're given. If every member landed within a
    /// few points of the requested frame, the group adopts the strictest (smallest) of them so no
    /// back window peeks out at an edge. A member that's much further off (a minimum size, a fixed
    /// size) is a misfit for corner parking (Phase 5) and doesn't move the group.
    static func reconcile(requested: CGRect, landed: [CGRect]) -> CGRect {
        let near = landed.filter { ExpectedFrames.close($0, requested) }
        guard !near.isEmpty else { return requested }
        let width = near.map(\.width).min()!, height = near.map(\.height).min()!
        return CGRect(x: requested.minX, y: requested.minY, width: width, height: height)
    }

    /// Green button click (PLAN.md §5.11): the outer frame fills the screen's usable area; a
    /// second click returns to the previous frame.
    static func fillToggle(outer: CGRect, previous: CGRect?, visibleFrame: CGRect) -> (outer: CGRect, previous: CGRect?) {
        if let previous, ExpectedFrames.close(outer, visibleFrame) { return (previous, nil) }
        return (visibleFrame, outer)
    }

    /// Where a group's members go when it's undone on quit (PLAN.md §5.12): the active tab keeps
    /// the outer frame (its strip space given back) and stays on top; each other tab is cascaded
    /// 22 pt right and down from the one before, wrapping to the start if it would leave the
    /// screen's usable area.
    static func cascade(outer: CGRect, activeFirst members: [CGWindowID], visibleFrame: CGRect, step: CGFloat = 22) -> [CGWindowID: CGRect] {
        var result: [CGWindowID: CGRect] = [:]
        var origin = outer.origin
        var wraps = 0
        for (i, id) in members.enumerated() {
            if i > 0 {
                origin = CGPoint(x: origin.x + step, y: origin.y + step)
                if origin.x + outer.width > visibleFrame.maxX || origin.y + outer.height > visibleFrame.maxY {
                    wraps += 1
                    origin = CGPoint(x: visibleFrame.minX + CGFloat(wraps) * step, y: visibleFrame.minY + CGFloat(wraps) * step)
                }
            }
            result[id] = CGRect(origin: origin, size: outer.size)
        }
        return result
    }

    /// Corner parking (PLAN.md §5.5): the window's top-left goes to the screen's bottom-right
    /// corner with 1 pt left on screen, the way AeroSpace hides windows.
    static func parkingOrigin(screen: CGRect) -> CGPoint {
        CGPoint(x: screen.maxX - 1, y: screen.maxY - 1)
    }
}
