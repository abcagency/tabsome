import Foundation

/// The product name lives here and in the `CFBundleDisplayName` build setting only (PLAN.md §10.7),
/// so renaming Tabsome is cheap.
enum Brand {
    static let name = "Tabsome"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.tabsome.app"
}
