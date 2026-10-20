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

    /// Top mode: the window buttons take the left end, then the tabs share the rest evenly
    /// (minimum widths and overflow arrive in Phase 4).
    static func tabFrames(stripWidth: CGFloat, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let start = tabsLeadingInset
        let available = max(0, stripWidth - start - tabsTrailingInset)
        let width = available / CGFloat(count)
        return (0..<count).map { CGRect(x: start + CGFloat($0) * width, y: 0, width: width, height: thickness(.top)) }
    }

    /// Buttons: inset + 3 × pitch, then a small gap before the first tab.
    static var tabsLeadingInset: CGFloat {
        Metrics.windowButtonLeadingInset + 2 * Metrics.windowButtonPitch + Metrics.windowButtonDiameter + 12
    }
    static let tabsTrailingInset: CGFloat = 8
}
