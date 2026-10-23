import CoreGraphics
import Foundation

/// What the next launch needs to undo the groups if Tabsome stops without running its quit
/// restore: a crash, Force Quit, or the Accessibility permission being turned off (PLAN.md
/// §5.12, §6.2 P7). Only window IDs, pids, bundle IDs, and frames (S4): no titles, no names.
nonisolated struct RecoveryState: Codable, Equatable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        var id: CGWindowID
        var pid: pid_t
        var bundleID: String?
    }

    struct Group: Codable, Equatable, Sendable {
        /// Strip plus window: the frame the active window grows back into.
        var outer: CGRect
        var active: Window
        var others: [Window]
        var minimized: Bool
    }

    var version = 1
    var groups: [Group] = []
}

/// The file itself, in Tabsome's Application Support folder (S8). Written whenever groups
/// change; removed when there are none, and after a quit restore where every window answered.
nonisolated enum RecoveryFile {
    static var url: URL { AppPaths.applicationSupport.appending(path: "recovery.json") }

    static func save(_ state: RecoveryState, to url: URL = url) {
        guard !state.groups.isEmpty else { return delete(at: url) }
        do {
            _ = try AppPaths.ensure(url.deletingLastPathComponent())
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            FileLog.shared.write("recovery: couldn't save (\(error.localizedDescription))")
        }
    }

    static func load(from url: URL = url) -> RecoveryState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RecoveryState.self, from: data)
    }

    static func delete(at url: URL = url) {
        try? FileManager.default.removeItem(at: url)
    }
}
