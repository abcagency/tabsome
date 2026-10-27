import CoreGraphics
import Foundation

/// One tabbed window (PLAN.md terminology: a "group"). Pure value type with the browser rules.
nonisolated struct TabGroup: Equatable, Identifiable {
    /// A quiet safety limit (PLAN.md §1): a full group stops accepting tabs, with no alert.
    static let maxTabs = 50

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
    func index(of id: CGWindowID) -> Int? { members.firstIndex(of: id) }

    /// Room for `incoming` more tabs under the limit.
    func canAccept(_ incoming: Int) -> Bool { members.count + incoming <= Self.maxTabs }

    /// New tabs go at the end of the strip by default (PLAN.md §5.3), or at a strip position
    /// (§5.2). Refused quietly past the limit.
    @discardableResult
    mutating func add(_ id: CGWindowID, at index: Int? = nil) -> Bool {
        insert([id], at: index)
    }

    /// Several tabs at once (a whole group merging in), keeping their order.
    @discardableResult
    mutating func insert(_ ids: [CGWindowID], at index: Int? = nil) -> Bool {
        let new = ids.filter { !members.contains($0) }
        guard canAccept(new.count) else { return false }
        let i = min(max(index ?? members.count, 0), members.count)
        members.insert(contentsOf: new, at: i)
        return true
    }

    /// Reorder (§5.7): the tab ends up at `index` in the new order.
    mutating func move(_ id: CGWindowID, to index: Int) {
        guard let from = members.firstIndex(of: id) else { return }
        members.remove(at: from)
        members.insert(id, at: min(max(index, 0), members.count))
    }

    /// Several tabs (in their strip order) to an insertion point counted with them still in
    /// place, as the strip's insertion marker counts it: a torn-out selection dropped back on
    /// its own strip.
    mutating func move(_ ids: [CGWindowID], to index: Int) {
        let moving = members.filter { ids.contains($0) }
        let before = members.prefix(max(0, min(index, members.count))).filter { ids.contains($0) }.count
        members.removeAll { ids.contains($0) }
        members.insert(contentsOf: moving, at: min(max(index - before, 0), members.count))
    }

    /// For "Close Other Tabs" / "Close Tabs to the Right" (§5.7). In Left mode "right" means below.
    func others(than id: CGWindowID) -> [CGWindowID] { members.filter { $0 != id } }
    func toTheRight(of id: CGWindowID) -> [CGWindowID] {
        guard let i = members.firstIndex(of: id) else { return [] }
        return Array(members[(i + 1)...])
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
