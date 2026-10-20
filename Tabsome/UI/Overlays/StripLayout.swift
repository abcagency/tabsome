import CoreGraphics

/// Where the tab strip sits (PLAN.md §5.6). Settings › Tabs gets the picker in Phase 6;
/// Left mode's strip view arrives in Phase 4.
nonisolated enum TabPlacement: String, CaseIterable, Sendable {
    case top, left
}

/// The one pure function behind every strip and content frame (PLAN.md §5.6), so the geometry
/// is tested once for both placements. All rects are global, top-left origin.
nonisolated enum StripLayout {
    static func thickness(_ placement: TabPlacement) -> CGFloat {
        switch placement {
        case .top: Metrics.topStripHeight
        case .left: Metrics.leftStripWidth
        }
    }

    /// Splits a group's outer frame into the strip and the members' (content) frame.
    static func frames(outer: CGRect, placement: TabPlacement) -> (strip: CGRect, content: CGRect) {
        let t = thickness(placement)
        switch placement {
        case .top:
            return (CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: t),
                    CGRect(x: outer.minX, y: outer.minY + t, width: outer.width, height: outer.height - t))
        case .left:
            return (CGRect(x: outer.minX, y: outer.minY, width: t, height: outer.height),
                    CGRect(x: outer.minX + t, y: outer.minY, width: outer.width - t, height: outer.height))
        }
    }

    /// The outer frame (strip + window) for a members' frame.
    static func outer(content: CGRect, placement: TabPlacement) -> CGRect {
        let t = thickness(placement)
        switch placement {
        case .top: return CGRect(x: content.minX, y: content.minY - t, width: content.width, height: content.height + t)
        case .left: return CGRect(x: content.minX - t, y: content.minY, width: content.width + t, height: content.height)
        }
    }

    /// Top mode: the window buttons take the left end, then the tabs share the rest evenly.
    /// (The full layout with overflow is `top(...)`; this is its frames.)
    static func tabFrames(stripWidth: CGFloat, count: Int) -> [CGRect] {
        top(width: stripWidth, count: count, active: 0, showsPlus: false).frames
    }

    /// How the tabs of one strip are laid out (PLAN.md §5.6).
    struct TopLayout: Equatable {
        enum Style: Equatable { case full, iconOnly }
        var style: Style
        /// Indexes into the group's tabs, in strip order, of the tabs that are shown.
        var visible: [Int]
        /// One frame per visible tab (strip coordinates, y down).
        var frames: [CGRect]
        /// Tabs that don't fit, listed in the » menu.
        var overflow: [Int]
        var overflowButton: CGRect?
        var plusButton: CGRect?

        /// Where a tab dropped at `x` would be inserted, as an index into all tabs (§5.2).
        func insertIndex(at x: CGFloat, count: Int) -> Int {
            for (k, frame) in frames.enumerated() where x < frame.midX { return visible[k] }
            return visible.last.map { $0 + 1 } ?? 0
        }

        /// The tab under `x`, if any.
        func tab(at x: CGFloat) -> Int? {
            frames.firstIndex { $0.minX <= x && x < $0.maxX }.map { visible[$0] }
        }

        /// The x of the insertion marker for an insert at `index`.
        func markerX(for index: Int) -> CGFloat? {
            if let k = visible.firstIndex(of: index) { return frames[k].minX }
            if let last = frames.last { return last.maxX }
            return nil
        }
    }

    static let minFullTabWidth: CGFloat = 90
    static let iconTabWidth: CGFloat = 40
    static let buttonWidth: CGFloat = 28

    /// Tabs share the width evenly with a minimum of about 90 pt; below that they shrink to
    /// icon-only, and when even those don't fit, the rest go into a » menu. The active tab is
    /// always visible. `frozenWidth` keeps widths still while the user closes tabs in a row.
    static func top(width: CGFloat, count: Int, active: Int, showsPlus: Bool, frozenWidth: CGFloat? = nil) -> TopLayout {
        guard count > 0 else { return TopLayout(style: .full, visible: [], frames: [], overflow: []) }
        let start = tabsLeadingInset
        let plus = showsPlus ? buttonWidth : 0
        let available = max(0, width - start - tabsTrailingInset - plus)
        let height = thickness(.top)

        func layout(_ visible: [Int], _ w: CGFloat, _ style: TopLayout.Style, overflow: [Int]) -> TopLayout {
            let frames = visible.indices.map { CGRect(x: start + CGFloat($0) * w, y: 0, width: w, height: height) }
            var x = start + CGFloat(visible.count) * w
            var result = TopLayout(style: style, visible: visible, frames: frames, overflow: overflow)
            if !overflow.isEmpty {
                result.overflowButton = CGRect(x: x, y: 0, width: buttonWidth, height: height)
                x += buttonWidth
            }
            if showsPlus { result.plusButton = CGRect(x: x, y: 0, width: buttonWidth, height: height) }
            return result
        }

        if let frozen = frozenWidth, frozen * CGFloat(count) <= available {
            return layout(Array(0..<count), frozen, frozen >= minFullTabWidth ? .full : .iconOnly, overflow: [])
        }
        let even = available / CGFloat(count)
        if even >= minFullTabWidth { return layout(Array(0..<count), even, .full, overflow: []) }
        if even >= iconTabWidth { return layout(Array(0..<count), even, .iconOnly, overflow: []) }
        // Overflow: as many icon tabs as fit next to the » button, always including the active one.
        let capacity = max(1, Int((available - buttonWidth) / iconTabWidth))
        var visible = Array(0..<min(capacity, count))
        if !visible.contains(active) { visible[visible.count - 1] = active }
        let overflow = (0..<count).filter { !visible.contains($0) }
        return layout(visible, iconTabWidth, .iconOnly, overflow: overflow)
    }

    /// Buttons: inset + 3 × pitch, then a small gap before the first tab.
    static var tabsLeadingInset: CGFloat {
        Metrics.windowButtonLeadingInset + 2 * Metrics.windowButtonPitch + Metrics.windowButtonDiameter + 12
    }
    static let tabsTrailingInset: CGFloat = 8
}
