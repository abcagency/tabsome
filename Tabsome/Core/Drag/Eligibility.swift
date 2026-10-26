import Carbon
import Foundation

/// Which windows may ever be tabbed (PLAN.md §6.1 S6). The hard-coded list can't be overridden
/// by users; the user's own list (Settings › Apps) adds to it.
nonisolated enum Eligibility {
    /// Authorization and Keychain prompts, password managers, Tabsome itself, and system
    /// surfaces. Users can't remove these.
    static let alwaysExcludedBundleIDs: Set<String> = [
        // Authorization, Keychain, and passwords
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent",
        "com.apple.LocalAuthentication.UIAgent",
        "com.apple.CoreAuthUI",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        // Password managers
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "com.dashlane.Dashlane",
        "org.keepassxc.keepassxc",
        "com.hicknhacksoftware.MacPass",
        "com.markmcguill.strongbox.mac",
        "in.sinew.Enpass-Desktop",
        "com.keepersecurity.passwordmanager",
        "com.nordsec.nordpass",
        "me.proton.pass.electron",
        "com.siber.roboform",
        "com.outercorner.Secrets",
        // System surfaces
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.WindowManager",
        "com.apple.screencaptureui",
        // Tabsome itself
        Bundle.main.bundleIdentifier ?? "com.tabsome.Tabsome",
    ]

    /// `excluded` is the user's own list (Settings › Apps).
    static func canTab(_ window: WindowSnapshot, bundleID: String?, excluded: Set<String> = ExcludedApps.bundleIDs) -> Bool {
        guard window.isStandard, !window.isMinimized, !window.isFullScreen else { return false }
        if let bundleID, alwaysExcludedBundleIDs.contains(bundleID) || excluded.contains(bundleID) { return false }
        return true
    }

    /// While secure input is on (a password field has focus somewhere), nothing is tabbed or
    /// captured.
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }
}

/// The user's list of apps Tabsome never tabs (Settings › Apps, PLAN.md §6.1 S6). Starts
/// with System Settings, whose panes and dialogs don't make sense as tabs.
nonisolated enum ExcludedApps {
    static let key = "excludedApps"
    static let defaultBundleIDs = ["com.apple.systempreferences"]

    static var list: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? defaultBundleIDs }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var bundleIDs: Set<String> { Set(list) }
}
