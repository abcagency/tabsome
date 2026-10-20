import AppKit
import CoreGraphics

/// One on-screen window as the window server sees it (no AX involved).
nonisolated struct ScreenWindow: Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    /// Global top-left-origin coordinates.
    let bounds: CGRect
}

/// CGWindowList reads. Used only during an active drag, at most 30 times a second for the full
/// list (PLAN.md §6.2 P2); the single-window query is cheaper (~0.7 ms, Phase 0).
nonisolated enum ScreenWindows {
    /// On-screen windows, front to back.
    static func onScreen() -> [ScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap(parse)
    }

    /// The window server's current bounds for one window.
    static func bounds(of id: CGWindowID) -> CGRect? {
        var pointer = UnsafeRawPointer(bitPattern: UInt(id))
        guard let ids = CFArrayCreate(nil, &pointer, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]],
              let info = list.first else { return nil }
        return parse(info)?.bounds
    }

    private static func parse(_ info: [String: Any]) -> ScreenWindow? {
        guard let id = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let layer = info[kCGWindowLayer as String] as? Int,
              let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
        return ScreenWindow(id: id, pid: pid, layer: layer, bounds: bounds)
    }
}
