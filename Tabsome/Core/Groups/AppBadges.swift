import AppKit

/// Matching Dock items to the apps on tabs (PLAN.md §5.14). Pure, so it's tested without a Dock.
nonisolated enum AppBadges {
    struct App: Equatable {
        let pid: pid_t
        let bundleURL: URL?
        let name: String
    }

    /// Each app's badge, by its bundle's location, or by name for an item with no URL. Apps
    /// without a badge are left out. Badges belong to the app, so every tab from it shows one.
    static func badges(items: [DockItem], apps: [App]) -> [pid_t: String] {
        var result: [pid_t: String] = [:]
        for app in apps {
            let path = app.bundleURL?.standardizedFileURL.path
            let item = items.first { item in
                if let url = item.url, let path { return url.standardizedFileURL.path == path }
                return item.url == nil && item.title == app.name
            }
            if let badge = item?.badge?.trimmingCharacters(in: .whitespacesAndNewlines), !badge.isEmpty { result[app.pid] = badge }
        }
        return result
    }

    /// What a tab shows for a badge, so a pill never crowds the name: a count above 9999
    /// (99 on an icon's corner) shows as "9999+" ("99+"), never as a cut-off number; other
    /// text is cut to 4 characters (3) with an ellipsis.
    static func display(_ badge: String, compact: Bool = false) -> String {
        let t = badge.trimmingCharacters(in: .whitespacesAndNewlines)
        let most = compact ? 99 : 9999
        if let n = Int(t.filter { $0.isNumber }), t.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." || $0.isWhitespace }) {
            return n > most ? "\(most)+" : t
        }
        let limit = compact ? 3 : 4
        return t.count > limit ? String(t.prefix(limit - 1)) + "…" : t
    }
}

/// The one timer Tabsome keeps (PLAN.md §5.14, a deliberate exception to §6.2 P2): while at
/// least one group exists and badges are on, it reads the Dock every 3 seconds, off the main
/// thread. It reads once as soon as it starts, and stops when the last group goes.
@MainActor
final class BadgeMonitor {
    static let interval: TimeInterval = 3

    var source: DockBadgeSource?
    /// The Dock items from the last read, delivered only when they changed.
    var onChange: (([DockItem]) -> Void)?
    private(set) var items: [DockItem] = []
    private var timer: Timer?
    private let interval: TimeInterval

    init(interval: TimeInterval = BadgeMonitor.interval) {
        self.interval = interval
    }

    var isRunning: Bool { timer != nil }

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive {
                readNow()
                timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.readNow() }
                }
                timer?.tolerance = interval / 3
            } else {
                timer?.invalidate()
                timer = nil
                set([]) // no stale badges if it starts again later
            }
        }
    }

    private func readNow() {
        source?.read { [weak self] items in
            guard let self, self.isActive, let items else { return }
            self.set(items)
        }
    }

    private func set(_ new: [DockItem]) {
        guard new != items else { return }
        items = new
        onChange?(new)
    }
}
