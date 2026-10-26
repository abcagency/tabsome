import AppKit

/// Stage Manager moves and resizes windows on its own, which conflicts with tabs (PLAN.md §8):
/// Tabsome warns when it's on.
enum StageManager {
    private static var domain: CFString { "com.apple.WindowManager" as CFString }

    static var isOn: Bool {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("GloballyEnabled" as CFString, domain) as? Bool ?? false
    }

    /// System Settings › Desktop & Dock, where Stage Manager is turned off.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
