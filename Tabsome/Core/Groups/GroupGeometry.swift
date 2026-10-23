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

    /// PLAN.md §5.8: macOS tiled the window (its green-button menu, Window › Move & Resize, the
    /// fn-⌃ arrow keys, or an edge drag): on each axis it spans the whole usable area or one half
    /// of it. The tolerance absorbs "Tiled windows have margins" and apps that round their frame,
    /// and stays below the strip's thickness, so a group's own content frame (inset by the strip)
    /// never reads as a tile.
    static func isTile(_ frame: CGRect, visibleFrame v: CGRect, tolerance: CGFloat = 20) -> Bool {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }
        func spans(_ lo: CGFloat, _ hi: CGFloat, _ vLo: CGFloat, _ vHi: CGFloat) -> Bool {
            let mid = (vLo + vHi) / 2
            return (near(lo, vLo) && near(hi, vHi)) || (near(lo, vLo) && near(hi, mid)) || (near(lo, mid) && near(hi, vHi))
        }
        return spans(frame.minX, frame.maxX, v.minX, v.maxX) && spans(frame.minY, frame.maxY, v.minY, v.maxY)
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

    /// Corner parking (PLAN.md §5.5): the window goes just past a corner of its screen with
    /// 1 pt left on it, the way AeroSpace hides windows. The corner is one where the window
    /// doesn't spill onto another display (bottom-right first); if every corner would, the one
    /// with the least overlap.
    static func parkingOrigin(screen: CGRect, size: CGSize, otherScreens: [CGRect] = []) -> CGPoint {
        let candidates = [
            CGPoint(x: screen.maxX - 1, y: screen.maxY - 1),                              // bottom-right
            CGPoint(x: screen.minX + 1 - size.width, y: screen.maxY - 1),                 // bottom-left
            CGPoint(x: screen.maxX - 1, y: screen.minY + 1 - size.height),                // top-right
            CGPoint(x: screen.minX + 1 - size.width, y: screen.minY + 1 - size.height),   // top-left
        ]
        func overlap(_ origin: CGPoint) -> CGFloat {
            let r = CGRect(origin: origin, size: size)
            return otherScreens.reduce(0) { total, s in
                let i = r.intersection(s)
                return total + (i.isNull ? 0 : i.width * i.height)
            }
        }
        return candidates.min { overlap($0) < overlap($1) } ?? candidates[0]
    }
}
