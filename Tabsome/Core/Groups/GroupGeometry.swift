import CoreGraphics

/// Pure frame math for groups.
nonisolated enum GroupGeometry {
    /// PLAN.md §5.5: the frame a group adopts once its members have answered.
    /// - A member that can't get small enough (a minimum size, or a fixed size bigger than the
    ///   group) makes the group grow to fit it, so every tab shares one frame.
    /// - Otherwise, some apps round the frame they're given: if every member landed within a few
    ///   points, the group adopts the strictest (smallest) of them so no back window peeks out.
    /// A member that came out much *smaller* (a maximum size) doesn't move the group; it's
    /// handled by concealment.
    static func reconcile(requested: CGRect, landed: [CGRect]) -> CGRect {
        let tolerance = ExpectedFrames.tolerance
        let wider = landed.map(\.width).filter { $0 > requested.width + tolerance }.max()
        let taller = landed.map(\.height).filter { $0 > requested.height + tolerance }.max()
        if wider != nil || taller != nil {
            return CGRect(origin: requested.origin, size: CGSize(width: wider ?? requested.width, height: taller ?? requested.height))
        }
        let near = landed.filter { ExpectedFrames.close($0, requested) }
        guard !near.isEmpty else { return requested }
        let width = near.map(\.width).min()!, height = near.map(\.height).min()!
        return CGRect(x: requested.minX, y: requested.minY, width: width, height: height)
    }

    /// A group that grew keeps its top-left where it can, but moves up and left as needed to
    /// stay inside the screen's usable area (or aligns to its top-left if it's bigger).
    static func keepOnScreen(_ outer: CGRect, visibleFrame v: CGRect) -> CGRect {
        var r = outer
        r.origin.x = max(v.minX, min(r.minX, v.maxX - r.width))
        r.origin.y = max(v.minY, min(r.minY, v.maxY - r.height))
        return r
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

    /// Concealment (PLAN.md §5.5): the size a window will take when asked for `request`, from
    /// what it took the last time it was asked for something. Per side: if it took what it was
    /// given (within the usual tolerance) it will again; if it came out bigger, a minimum held
    /// it; smaller, a maximum.
    static func predictedSize(for request: CGSize, last: (requested: CGSize, landed: CGSize)?) -> CGSize {
        guard let last else { return request }
        func side(_ r: CGFloat, _ asked: CGFloat, _ took: CGFloat) -> CGFloat {
            if abs(took - asked) <= ExpectedFrames.tolerance { return r }
            return took > asked ? max(took, r) : min(took, r)
        }
        return CGSize(width: side(request.width, last.requested.width, last.landed.width),
                      height: side(request.height, last.requested.height, last.landed.height))
    }

    /// Whether a background window of size `back`, at the same top-left corner as the front one,
    /// is hidden behind it. One that isn't would show around the active tab.
    static func isCovered(_ back: CGSize, by front: CGSize) -> Bool {
        back.width <= front.width + ExpectedFrames.tolerance && back.height <= front.height + ExpectedFrames.tolerance
    }

    /// After a display change (PLAN.md §5.8): nil while the group is mostly on some screen;
    /// otherwise the frame to move it to, on the screen it overlaps most (or the first one),
    /// shrunk to fit if it has to be.
    static func refitToScreens(outer: CGRect, visibleFrames: [CGRect]) -> CGRect? {
        guard !visibleFrames.isEmpty else { return nil }
        func overlap(_ s: CGRect) -> CGFloat {
            let i = outer.intersection(s)
            return i.isNull ? 0 : i.width * i.height
        }
        let best = visibleFrames.max { overlap($0) < overlap($1) }!
        if overlap(best) >= outer.width * outer.height / 2 { return nil }
        let target = overlap(best) > 0 ? best : visibleFrames[0]
        let size = CGSize(width: min(outer.width, target.width), height: min(outer.height, target.height))
        let x = min(max(outer.minX, target.minX), target.maxX - size.width)
        let y = min(max(outer.minY, target.minY), target.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
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
