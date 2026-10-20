import Foundation

/// The only places Tabsome writes to disk (PLAN.md §6.1 S8): its own Application Support and
/// Logs folders. Preferences go through `UserDefaults`.
enum AppPaths {
    static var applicationSupport: URL {
        URL.applicationSupportDirectory.appending(path: Brand.name, directoryHint: .isDirectory)
    }

    static var logs: URL {
        URL.libraryDirectory.appending(path: "Logs/\(Brand.name)", directoryHint: .isDirectory)
    }

    /// Creates the folder if needed and returns it.
    static func ensure(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
