import AppKit

/// Owns the app's long-lived objects and wires them together.
@MainActor
@Observable
final class AppModel {
    let permissions = Permissions()
    let registry: WindowRegistry
    let appearance = AppearanceController()
    let launchAtLogin = LaunchAtLogin()

    @ObservationIgnored private lazy var onboarding = OnboardingWindowController(model: self)

    static let onboardingCompletedKey = "onboardingCompleted"
    var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardingCompletedKey) }
    }

    init(windowSystem: WindowSystem = AXWindowSystem()) {
        registry = WindowRegistry(system: windowSystem)
        permissions.onAccessibilityChange = { [weak self] granted in
            guard let self else { return }
            // Without the permission Tabsome stops all behavior (PLAN.md §5.8).
            if granted { registry.start() } else { registry.stop() }
        }
        registry.onAccessibilityDisabled = { [weak self] in self?.permissions.refresh() }
    }

    var needsOnboarding: Bool { !permissions.accessibility || !onboardingCompleted }

    func startIfPermitted() {
        if permissions.accessibility { registry.start() }
    }

    func showOnboarding() { onboarding.show() }
}
