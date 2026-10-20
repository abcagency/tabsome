import CoreGraphics

/// Where the tab strip sits, and in Left mode how wide (PLAN.md §5.6): Settings › Tabs.
nonisolated enum TabPlacement: String, CaseIterable, Sendable {
    /// A horizontal strip above the window: icon and app name per tab.
    case top
    /// Compact Left: a narrow column of app icons, no text.
    case left
    /// Left with names: a wider column with icon, name (ellipsis when long), and × on hover.
    case leftNamed

    var isLeft: Bool { self != .top }
}

/// The one pure function behind every strip and content frame (PLAN.md §5.6), so the geometry
/// is tested once for both placements. All rects are global, top-left origin.
nonisolated enum StripLayout {
    static func thickness(_ placement: TabPlacement) -> CGFloat {
        switch placement {
        case .top: Metrics.topStripHeight
        case .left: Metrics.leftStripWidth
        case .leftNamed: Metrics.leftNamedStripWidth
        }
    }

    /// Splits a group's outer frame into the strip and the members' (content) frame.
    static func frames(outer: CGRect, placement: TabPlacement) -> (strip: CGRect, content: CGRect) {
        let t = thickness(placement)
        switch placement {
        case .top:
            return (CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: t),
                    CGRect(x: outer.minX, y: outer.minY + t, width: outer.width, height: outer.height - t))
        case .left, .leftNamed:
            return (CGRect(x: outer.minX, y: outer.minY, width: t, height: outer.height),
                    CGRect(x: outer.minX + t, y: outer.minY, width: outer.width - t, height: outer.height))
        }
    }

    /// The outer frame (strip + window) for a members' frame.
    static func outer(content: CGRect, placement: TabPlacement) -> CGRect {
        let t = thickness(placement)
        switch placement {
        case .top: return CGRect(x: content.minX, y: content.minY - t, width: content.width, height: content.height + t)
        case .left, .leftNamed: return CGRect(x: content.minX - t, y: content.minY, width: content.width + t, height: content.height)
        }
    }

    /// Top mode: the window buttons take the left end, then the tabs share the rest evenly.
    /// (The full layout with overflow is `top(...)`; this is its frames.)
    static func tabFrames(stripWidth: CGFloat, count: Int) -> [CGRect] {
        top(width: stripWidth, count: count, active: 0, showsPlus: false).frames
    }

    /// How the tabs of one strip are laid out (PLAN.md §5.6): along x in Top mode, along y in Left.
    struct TabsLayout: Equatable {
        enum Style: Equatable { case full, iconOnly }
        var style: Style
        var vertical = false
        /// Indexes into the group's tabs, in strip order, of the tabs that are shown.
        var visible: [Int]
        /// One frame per visible tab (strip coordinates, y down).
        var frames: [CGRect]
        /// Tabs that don't fit, listed in the » menu.
        var overflow: [Int]
        var overflowButton: CGRect?
        var plusButton: CGRect?

        private func lo(_ r: CGRect) -> CGFloat { vertical ? r.minY : r.minX }
        private func mid(_ r: CGRect) -> CGFloat { vertical ? r.midY : r.midX }
        private func hi(_ r: CGRect) -> CGFloat { vertical ? r.maxY : r.maxX }

        /// Where a tab dropped at `position` (x in Top mode, y in Left) would be inserted, as an
        /// index into all tabs (§5.2).
        func insertIndex(at position: CGFloat, count: Int) -> Int {
            for (k, frame) in frames.enumerated() where position < mid(frame) { return visible[k] }
            return visible.last.map { $0 + 1 } ?? 0
        }

        /// The tab under `position`, if any.
        func tab(at position: CGFloat) -> Int? {
            frames.firstIndex { lo($0) <= position && position < hi($0) }.map { visible[$0] }
        }

        /// Where the insertion marker goes for an insert at `index` (x in Top mode, y in Left).
        func markerPosition(for index: Int) -> CGFloat? {
            if let k = visible.firstIndex(of: index) { return lo(frames[k]) }
            if let last = frames.last { return hi(last) }
            return nil
        }

        /// The slot size along the strip (all slots are equal unless one tab is being renamed).
        var slotLength: CGFloat { frames.first.map { vertical ? $0.height : $0.width } ?? 0 }
    }

    static let minFullTabWidth: CGFloat = 90
    static let iconTabWidth: CGFloat = 40
    static let buttonWidth: CGFloat = 28

    /// Tabs share the width evenly with a minimum of about 90 pt; below that they shrink to
    /// icon-only, and when even those don't fit, the rest go into a » menu. The active tab is
    /// always visible. `frozenWidth` keeps widths still while the user closes tabs in a row.
    static func top(width: CGFloat, count: Int, active: Int, showsPlus: Bool, frozenWidth: CGFloat? = nil,
                    wide: (index: Int, width: CGFloat)? = nil) -> TabsLayout {
        guard count > 0 else { return TabsLayout(style: .full, visible: [], frames: [], overflow: []) }
        let start = tabsLeadingInset
        let plus = showsPlus ? buttonWidth : 0
        let available = max(0, width - start - tabsTrailingInset - plus)
        let height = thickness(.top)

        func layout(_ visible: [Int], _ w: CGFloat, _ style: TabsLayout.Style, overflow: [Int]) -> TabsLayout {
            let frames = visible.indices.map { CGRect(x: start + CGFloat($0) * w, y: 0, width: w, height: height) }
            var x = start + CGFloat(visible.count) * w
            var result = TabsLayout(style: style, visible: visible, frames: frames, overflow: overflow)
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
        // One tab wider than the rest (being renamed): the others share what's left, never below
        // the full-tab minimum while the wide one is still growing.
        if let wide, count > 1, wide.index < count, wide.width > even {
            let others = CGFloat(count - 1)
            let w = min(wide.width, available - others * min(even, minFullTabWidth))
            let rest = (available - w) / others
            if w > even, rest >= iconTabWidth {
                var frames: [CGRect] = []
                var x = start
                for i in 0..<count {
                    let tw = i == wide.index ? w : rest
                    frames.append(CGRect(x: x, y: 0, width: tw, height: height))
                    x += tw
                }
                var result = TabsLayout(style: rest >= minFullTabWidth ? .full : .iconOnly, visible: Array(0..<count), frames: frames, overflow: [])
                if showsPlus { result.plusButton = CGRect(x: x, y: 0, width: buttonWidth, height: height) }
                return result
            }
        }
        if even >= minFullTabWidth { return layout(Array(0..<count), even, .full, overflow: []) }
        if even >= iconTabWidth { return layout(Array(0..<count), even, .iconOnly, overflow: []) }
        // Overflow: as many icon tabs as fit next to the » button, always including the active one.
        let capacity = max(1, Int((available - buttonWidth) / iconTabWidth))
        var visible = Array(0..<min(capacity, count))
        if !visible.contains(active) { visible[visible.count - 1] = active }
        let overflow = (0..<count).filter { !visible.contains($0) }
        return layout(visible, iconTabWidth, .iconOnly, overflow: overflow)
    }

    /// Left mode (PLAN.md §5.6): a 40 pt column of 28 pt icons, one per tab, with "+" below the
    /// last one. When the tabs outgrow the window's height, the rest go into a » menu at the bottom
    /// (the active tab always stays visible).
    static func left(height: CGFloat, count: Int, active: Int, showsPlus: Bool, named: Bool = false) -> TabsLayout {
        let w = thickness(named ? .leftNamed : .left)
        let style: TabsLayout.Style = named ? .full : .iconOnly
        guard count > 0 else { return TabsLayout(style: style, vertical: true, visible: [], frames: [], overflow: []) }
        let start = leftTopInset, slot = named ? leftNamedRowHeight : leftSlotHeight
        let plus = showsPlus ? buttonWidth : 0
        let available = max(0, height - start - leftTopInset - plus)

        func layout(_ visible: [Int], overflow: [Int]) -> TabsLayout {
            let frames = visible.indices.map { CGRect(x: 0, y: start + CGFloat($0) * slot, width: w, height: slot) }
            var y = start + CGFloat(visible.count) * slot
            var result = TabsLayout(style: style, vertical: true, visible: visible, frames: frames, overflow: overflow)
            if !overflow.isEmpty {
                result.overflowButton = CGRect(x: 0, y: y, width: w, height: buttonWidth)
                y += buttonWidth
            }
            if showsPlus { result.plusButton = CGRect(x: 0, y: y, width: w, height: buttonWidth) }
            return result
        }

        if CGFloat(count) * slot <= available { return layout(Array(0..<count), overflow: []) }
        let capacity = max(1, Int((available - buttonWidth) / slot))
        var visible = Array(0..<min(capacity, count))
        if !visible.contains(active) { visible[visible.count - 1] = active }
        return layout(visible, overflow: (0..<count).filter { !visible.contains($0) })
    }

    static let leftTopInset: CGFloat = 8
    static let leftSlotHeight: CGFloat = 36
    static let leftIconSize: CGFloat = 28
    static let leftNamedRowHeight: CGFloat = 30
    static let leftNamedIconSize: CGFloat = 18

    /// Buttons: inset + 3 × pitch, then a small gap before the first tab.
    static var tabsLeadingInset: CGFloat {
        Metrics.windowButtonLeadingInset + 2 * Metrics.windowButtonPitch + Metrics.windowButtonDiameter + 12
    }
    static let tabsTrailingInset: CGFloat = 8
}
