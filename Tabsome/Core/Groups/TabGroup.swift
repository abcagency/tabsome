import CoreGraphics
import Foundation

/// One tabbed window (PLAN.md terminology: a "group"). Pure value type with the browser rules.
nonisolated struct TabGroup: Equatable, Identifiable {
    let id: UUID
    private(set) var members: [CGWindowID]
    private(set) var activeID: CGWindowID
    /// The members' shared frame (global, top-left origin). The strip sits outside it.
    var content: CGRect
    var placement: TabPlacement = .top
    /// The outer frame before the last Fill, for the second green click (PLAN.md §5.11).
    var previousOuter: CGRect?
    var isMinimized = false

    init(id: UUID = UUID(), members: [CGWindowID], active: CGWindowID, content: CGRect, placement: TabPlacement = .top) {
        precondition(members.contains(active))
        self.id = id
        self.members = members
        self.activeID = active
        self.content = content
        self.placement = placement
    }

    var outer: CGRect { StripLayout.outer(content: content, placement: placement) }
    var count: Int { members.count }
    var activeIndex: Int { members.firstIndex(of: activeID)! }
    var inactive: [CGWindowID] { members.filter { $0 != activeID } }

    func contains(_ id: CGWindowID) -> Bool { members.contains(id) }

    /// New tabs go at the end of the strip by default (PLAN.md §5.3).
    mutating func add(_ id: CGWindowID, at index: Int? = nil) {
        guard !members.contains(id) else { return }
        let i = min(max(index ?? members.count, 0), members.count)
        members.insert(id, at: i)
    }

    mutating func activate(_ id: CGWindowID) {
        guard members.contains(id) else { return }
        activeID = id
    }

    /// Removes a tab. If it was active, the tab to its right becomes active, or the one to its
    /// left if it was last, like a browser (PLAN.md §5.7). Returns the new active tab if it changed.
    @discardableResult
    mutating func remove(_ id: CGWindowID) -> CGWindowID? {
        guard let i = members.firstIndex(of: id) else { return nil }
        members.remove(at: i)
        guard id == activeID, !members.isEmpty else { return nil }
        activeID = members[min(i, members.count - 1)]
        return activeID
    }

    /// A group of one is just a window again (PLAN.md §5.8).
    var shouldDissolve: Bool { members.count < 2 }
}
