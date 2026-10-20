import CoreGraphics

/// The "middle" of a target window (PLAN.md §5.2): the frame inset by 25% on each side, so
/// a drag that merely passes over a window, or nears its edges, doesn't trigger.
nonisolated enum DropZone {
    /// Fraction of the width/height inset from each side (0.25 → the central 50% × 50%).
    static let defaultInset: CGFloat = 0.25

    static func middle(of frame: CGRect, inset: CGFloat = defaultInset) -> CGRect {
        frame.insetBy(dx: frame.width * inset, dy: frame.height * inset)
    }

    static func contains(_ point: CGPoint, frame: CGRect, inset: CGFloat = defaultInset) -> Bool {
        middle(of: frame, inset: inset).contains(point)
    }
}
