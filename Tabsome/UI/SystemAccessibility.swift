import AppKit

/// Live Reduce Motion / Reduce Transparency / Increase Contrast state (PLAN.md §5.9), and
/// whether the accent color is Graphite (window buttons turn grey, like macOS).
/// Changes arrive by notification, so there's no polling.
@MainActor
@Observable
final class SystemAccessibility {
    static let shared = SystemAccessibility()

    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false
    /// System Settings › Appearance › Accent color = Graphite.
    private(set) var graphiteAccent = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        read()
        let reread: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main, using: reread),
            NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main, using: reread),
            DistributedNotificationCenter.default().addObserver(forName: .init("AppleColorPreferencesChangedNotification"), object: nil, queue: .main, using: reread),
        ]
    }

    private func read() {
        let ws = NSWorkspace.shared
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
        reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
        increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
        // -1 is Graphite; no value means Multicolor.
        graphiteAccent = (UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int) == -1
    }
}
