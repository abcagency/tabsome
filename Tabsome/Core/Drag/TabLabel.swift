import AppKit

/// What a tab shows (PLAN.md §5.6, §10.2): the app's full name, plus the window title only
/// when two tabs come from the same app. Custom names (§5.10) arrive in Phase 4.
struct GhostTab: Equatable, Identifiable {
    let id: CGWindowID
    let label: String
    let pid: pid_t
    let isNew: Bool
}

@MainActor
enum TabLabel {
    static func label(for entry: WindowRegistry.Entry, among entries: [WindowRegistry.Entry]) -> String {
        let sameApp = entries.filter { $0.app.pid == entry.app.pid }.count > 1
        guard sameApp, let title = entry.window.title, !title.isEmpty else { return entry.app.name }
        return "\(entry.app.name) — \(title)"
    }

    /// The preview strip: the target's tabs, then the dragged window (or group) appended (§5.3).
    static func ghostTabs(existing: [WindowRegistry.Entry], adding new: [WindowRegistry.Entry]) -> [GhostTab] {
        let all = existing + new
        let newIDs = Set(new.map(\.id))
        return all.map { GhostTab(id: $0.id, label: label(for: $0, among: all), pid: $0.app.pid, isNew: newIDs.contains($0.id)) }
    }
}
