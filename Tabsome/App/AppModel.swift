import AppKit

/// Owns the app's long-lived objects and wires them together.
@MainActor
@Observable
final class AppModel {
    let permissions = Permissions()
    let registry: WindowRegistry
    let groups: GroupManager
    let appearance = AppearanceController()
    let launchAtLogin = LaunchAtLogin()
    @ObservationIgnored private(set) lazy var drag = DragCoordinator(registry: registry, groups: groups)

    @ObservationIgnored private lazy var onboarding = OnboardingWindowController(model: self)

    static let onboardingCompletedKey = "onboardingCompleted"
    var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardingCompletedKey) }
    }

    init(windowSystem: WindowSystem = AXWindowSystem()) {
        registry = WindowRegistry(system: windowSystem)
        groups = GroupManager(registry: registry, system: windowSystem)
        groups.confirmCloseAll = Self.confirmCloseAll
        permissions.onAccessibilityChange = { [weak self] granted in
            guard let self else { return }
            // Without the permission Tabsome stops all behavior (PLAN.md §5.8).
            if granted { start() } else { stopAll() }
        }
        registry.onAccessibilityDisabled = { [weak self] in self?.permissions.refresh() }
    }

    var needsOnboarding: Bool { !permissions.accessibility || !onboardingCompleted }

    func startIfPermitted() {
        if permissions.accessibility { start() }
    }

    private func start() {
        registry.start()
        groups.targeting = drag
        drag.start()
    }

    func stopAll() {
        drag.stop()
        groups.abandonAll()
        registry.stop()
    }

    /// Quit (PLAN.md §5.12): stop new drags, untab everything, close nothing, then stop.
    func restoreAndStop(done: @escaping () -> Void) {
        drag.stop()
        groups.restoreAll(timeout: 2) { [weak self] in
            self?.registry.stop()
            done()
        }
    }

    static let askBeforeClosingAllKey = "askBeforeClosingAllTabs"

    /// Like Safari: "Close N tabs?" with "Don't ask again" (PLAN.md §5.11).
    private static func confirmCloseAll(_ count: Int) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: askBeforeClosingAllKey) != nil, !defaults.bool(forKey: askBeforeClosingAllKey) { return true }
        let alert = NSAlert()
        alert.messageText = "Close \(count) tabs?"
        alert.informativeText = "Each app closes its own window, and asks first if something needs saving."
        alert.addButton(withTitle: "Close \(count) Tabs")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"
        NSApp.activate()
        let ok = alert.runModal() == .alertFirstButtonReturn
        if ok, alert.suppressionButton?.state == .on { defaults.set(false, forKey: askBeforeClosingAllKey) }
        return ok
    }

    func showOnboarding() { onboarding.show() }
}
