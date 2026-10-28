import Foundation

/// The product name lives in the `CFBundleDisplayName` build setting (PLAN.md §10.7), so renaming
/// Tabsome is cheap. Debug builds are "Tabsome Dev" (`com.tabsome.app.dev`): a separate app to
/// macOS, with its own Privacy & Security entries, settings, logs, and recovery file, so it and an
/// installed release can both stay allowed.
enum Brand {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Tabsome"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.tabsome.app"
}
