import os

/// Unified-logging categories. Window titles and tab names are sensitive (PLAN.md §6.1 S4):
/// interpolate them only with `privacy: .private`, and never pass them to `FileLog`.
enum Log {
    private static let subsystem = Brand.bundleID
    static let app = Logger(subsystem: subsystem, category: "app")
    static let ax = Logger(subsystem: subsystem, category: "ax")
    static let registry = Logger(subsystem: subsystem, category: "registry")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
