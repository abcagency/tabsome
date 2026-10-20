import Carbon
import Foundation

/// Which windows may ever be tabbed (PLAN.md §6.1 S6). The hard-coded list can't be overridden
/// by users; Phase 5 extends it and adds the user's own exclusions.
nonisolated enum Eligibility {
    /// Authorization and Keychain prompts, password managers, and system surfaces.
    static let alwaysExcludedBundleIDs: Set<String> = [
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
    ]

    static func canTab(_ window: WindowSnapshot, bundleID: String?) -> Bool {
        guard window.isStandard, !window.isMinimized, !window.isFullScreen else { return false }
        if let bundleID, alwaysExcludedBundleIDs.contains(bundleID) { return false }
        return true
    }

    /// While secure input is on (a password field has focus somewhere), nothing is tabbed.
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }
}
