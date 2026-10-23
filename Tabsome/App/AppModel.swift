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
    @ObservationIgnored let hotKeys = HotKeys()

    static let tabPlacementKey = "tabPlacement"
    /// Settings › Tabs › Tab position (PLAN.md §5.6). Applies to every group live.
    var tabPlacement: TabPlacement {
        didSet {
            UserDefaults.standard.set(tabPlacement.rawValue, forKey: Self.tabPlacementKey)
            groups.setPlacement(tabPlacement)
        }
    }
    @ObservationIgnored private(set) lazy var drag = DragCoordinator(registry: registry, groups: groups)

    static let pausedKey = "paused"
    /// Settings › General › Pause (PLAN.md §5.12): every group is undone, nothing is closed, and
    /// no new groups form until it's turned off. Groups don't come back afterwards.
    var isPaused: Bool = UserDefaults.standard.bool(forKey: AppModel.pausedKey) {
        didSet {
            guard isPaused != oldValue else { return }
            UserDefaults.standard.set(isPaused, forKey: Self.pausedKey)
            FileLog.shared.write(isPaused ? "paused" : "resumed")
            guard registry.isRunning else { return }
            if isPaused {
                drag.stop()
                groups.restoreAll(timeout: 2) { allLanded in if allLanded { RecoveryFile.delete() } }
            } else {
                drag.start()
            }
        }
    }

    @ObservationIgnored private lazy var onboarding = OnboardingWindowController(model: self)

    static let onboardingCompletedKey = "onboardingCompleted"
    var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardingCompletedKey) }
    }

    init(windowSystem: WindowSystem = AXWindowSystem()) {
        registry = WindowRegistry(system: windowSystem)
        groups = GroupManager(registry: registry, system: windowSystem)
        tabPlacement = UserDefaults.standard.string(forKey: Self.tabPlacementKey).flatMap(TabPlacement.init(rawValue:)) ?? .top
        groups.setPlacement(tabPlacement)
        groups.confirmCloseAll = Self.confirmCloseAll
        hotKeys.onAction = { [weak self] action in self?.groups.perform(action) }
        // Registered only while a group is focused, so the keys reach other apps otherwise.
        groups.onFocusedGroupChanged = { [weak self] gid in self?.hotKeys.isEnabled = gid != nil }
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
        // Groups left over from a crash, Force Quit, or the permission being turned off are
        // undone first, the way Quit would have (§5.12). Then every change is saved again.
        if let leftover = RecoveryFile.load(), !leftover.groups.isEmpty {
            FileLog.shared.write("recovery file found: groups=\(leftover.groups.count)")
            groups.recover(leftover) { [weak self] in
                guard let self else { return }
                RecoveryFile.save(self.groups.recoveryState())
            }
        }
        groups.onRecoveryStateChanged = { RecoveryFile.save($0) }
        if !isPaused { drag.start() }
    }

    /// Accessibility turned off, or the app is exiting. Groups are let go where they are; the
    /// recovery file keeps them for the next start.
    func stopAll() {
        hotKeys.isEnabled = false
        drag.stop()
        groups.onRecoveryStateChanged = nil
        groups.abandonAll()
        registry.stop()
    }

    /// Quit (PLAN.md §5.12): stop new drags, untab everything, close nothing, then stop.
    func restoreAndStop(done: @escaping () -> Void) {
        drag.stop()
        groups.onRecoveryStateChanged = nil
        groups.restoreAll(timeout: 2) { [weak self] allLanded in
            // A window that didn't answer in time is fixed from the file on the next launch.
            if allLanded { RecoveryFile.delete() }
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
