import Foundation

/// The only places Tabsome writes to disk (PLAN.md §6.1 S8): its own Application Support and
/// Logs folders. Preferences go through `UserDefaults`.
enum AppPaths {
    /// Unit tests run inside the app. They get a throwaway folder instead, so a test run never
    /// writes into the user's log or recovery file.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let testRoot = FileManager.default.temporaryDirectory
        .appending(path: "\(Brand.name)Tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)

    static var applicationSupport: URL {
        isRunningTests ? testRoot.appending(path: "Application Support", directoryHint: .isDirectory)
            : URL.applicationSupportDirectory.appending(path: Brand.name, directoryHint: .isDirectory)
    }

    static var logs: URL {
        isRunningTests ? testRoot.appending(path: "Logs", directoryHint: .isDirectory)
            : URL.libraryDirectory.appending(path: "Logs/\(Brand.name)", directoryHint: .isDirectory)
    }

    /// Creates the folder if needed and returns it.
    static func ensure(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
