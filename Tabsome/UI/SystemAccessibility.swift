import AppKit

/// Live Reduce Motion / Reduce Transparency / Increase Contrast state (PLAN.md §5.9).
/// Changes arrive by notification, so there's no polling.
@MainActor
@Observable
final class SystemAccessibility {
    static let shared = SystemAccessibility()

    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false

    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        read()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private func read() {
        let ws = NSWorkspace.shared
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
        reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
        increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
    }
}
