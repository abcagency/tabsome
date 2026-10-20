import CoreGraphics

/// Selecting several tabs (like Chrome and Safari): ⇧-click selects the range from the anchor
/// to the clicked tab, ⌘-click adds or removes one tab, a plain click selects just that tab.
/// Dragging any selected tab carries the whole selection (PLAN.md §5.7). Pure.
nonisolated struct TabSelection: Equatable {
    /// Always contains the active tab.
    private(set) var selected: Set<CGWindowID>
    /// Where the next ⇧-click range starts.
    private(set) var anchor: CGWindowID

    init(active: CGWindowID) {
        selected = [active]
        anchor = active
    }

    enum Modifier { case none, shift, command }

    /// Applies a click on `tab` in a strip whose tabs are `order`. Returns whether the clicked
    /// tab becomes active (a ⌘-click that deselects doesn't switch to it).
    mutating func click(_ tab: CGWindowID, modifier: Modifier, order: [CGWindowID], active: CGWindowID) -> Bool {
        switch modifier {
        case .none:
            // A press on a tab that's already part of a selection keeps the selection, so the
            // whole selection can be dragged; `collapse` runs if the press ends without a drag.
            if !(selected.contains(tab) && selected.count > 1) { selected = [tab] }
            anchor = tab
            return true
        case .shift:
            guard let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: tab) else {
                selected = [tab]
                anchor = tab
                return true
            }
            selected = Set(order[min(a, b)...max(a, b)])
            return true
        case .command:
            if selected.contains(tab), selected.count > 1 {
                // The active tab can't be deselected; any other selected tab can.
                if tab != active { selected.remove(tab) }
                return false
            }
            selected.insert(tab)
            anchor = tab
            return true
        }
    }

    /// A plain click that didn't turn into a drag: just that tab.
    mutating func collapse(to tab: CGWindowID) {
        selected = [tab]
        anchor = tab
    }

    /// Keeps the selection valid after tabs change: only current tabs, and always the active one.
    mutating func prune(to order: [CGWindowID], active: CGWindowID) {
        selected = selected.intersection(order).union([active])
        if !order.contains(anchor) { anchor = active }
    }

    /// The selection in strip order.
    func ordered(_ order: [CGWindowID]) -> [CGWindowID] { order.filter(selected.contains) }
    var count: Int { selected.count }
}
