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

    /// Settings › Apps (PLAN.md §6.1 S6): apps Tabsome never tabs. Adding one takes its windows
    /// out of their groups right away.
    var excludedApps: [String] = ExcludedApps.list {
        didSet {
            ExcludedApps.list = excludedApps
            groups.removeExcluded(Set(excludedApps))
        }
    }

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

    static let shortcutsEnabledKey = "shortcutsEnabled"
    /// Settings › Shortcuts › "Use keyboard shortcuts" (on by default).
    var shortcutsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(shortcutsEnabled, forKey: Self.shortcutsEnabledKey)
            hotKeys.isAllowed = shortcutsEnabled
        }
    }

    static let dwellDelayKey = "dwellDelay"
    static let dwellDelayRange: ClosedRange<Double> = 0.2...1.0
    /// Settings › General: how long to pause over a window before it's ready to tab (§5.3).
    var dwellDelay: Double {
        didSet {
            UserDefaults.standard.set(dwellDelay, forKey: Self.dwellDelayKey)
            drag.dwellDelay = dwellDelay
        }
    }

    static let middleZoneKey = "middleZone"
    static let middleZoneRange: ClosedRange<Double> = 0.3...0.7
    /// Settings › General: how much of a window counts as its middle (§5.2), as a fraction of
    /// its width and height (0.5 is the central 50% × 50%).
    var middleZone: Double {
        didSet {
            UserDefaults.standard.set(middleZone, forKey: Self.middleZoneKey)
            drag.middleInset = (1 - middleZone) / 2
        }
    }

    static let stripSizeKey = "stripSize", minTabWidthKey = "minTabWidth", showCloseButtonsKey = "showCloseButtons"
    static let showBadgesKey = "showAppBadges"
    /// Settings › Tabs: strip size, tab min width, and close buttons. Applies to every group live.
    var stripOptions: StripOptions {
        didSet {
            let d = UserDefaults.standard
            d.set(stripOptions.size.rawValue, forKey: Self.stripSizeKey)
            d.set(Double(stripOptions.minTabWidth), forKey: Self.minTabWidthKey)
            d.set(stripOptions.showsCloseButtons, forKey: Self.showCloseButtonsKey)
            d.set(stripOptions.showsBadges, forKey: Self.showBadgesKey)
            groups.setStripOptions(stripOptions)
        }
    }

    private static func savedStripOptions(_ d: UserDefaults) -> StripOptions {
        var o = StripOptions()
        if let size = d.string(forKey: stripSizeKey).flatMap(StripSize.init(rawValue:)) { o.size = size }
        if d.object(forKey: minTabWidthKey) != nil {
            o.minTabWidth = min(max(CGFloat(d.double(forKey: minTabWidthKey)), StripOptions.minTabWidthRange.lowerBound), StripOptions.minTabWidthRange.upperBound)
        }
        if d.object(forKey: showCloseButtonsKey) != nil { o.showsCloseButtons = d.bool(forKey: showCloseButtonsKey) }
        if d.object(forKey: showBadgesKey) != nil { o.showsBadges = d.bool(forKey: showBadgesKey) }
        return o
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
        let defaults = UserDefaults.standard
        tabPlacement = defaults.string(forKey: Self.tabPlacementKey).flatMap(TabPlacement.init(rawValue:)) ?? .top
        let dwell = defaults.object(forKey: Self.dwellDelayKey) as? Double ?? DwellStateMachine.Config().dwell
        dwellDelay = min(max(dwell, Self.dwellDelayRange.lowerBound), Self.dwellDelayRange.upperBound)
        let zone = defaults.object(forKey: Self.middleZoneKey) as? Double ?? 1 - 2 * DropZone.defaultInset
        middleZone = min(max(zone, Self.middleZoneRange.lowerBound), Self.middleZoneRange.upperBound)
        stripOptions = Self.savedStripOptions(defaults)
        shortcutsEnabled = defaults.object(forKey: Self.shortcutsEnabledKey) as? Bool ?? true
        hotKeys.isAllowed = shortcutsEnabled
        groups.badges.source = DockBadgeReader()
        groups.setStripOptions(stripOptions)
        groups.setPlacement(tabPlacement)
        drag.dwellDelay = dwellDelay
        drag.middleInset = (1 - middleZone) / 2
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
        groups.onFight = { appName, bundleID in
            // After the event that found it, not inside it: the notice is a modal alert.
            DispatchQueue.main.async {
                Self.showOnce("fight.\(bundleID ?? appName)",
                             title: "\(appName) was taken out of its tab group",
                             message: "Something keeps moving \(appName)’s window back each time Tabsome places it, such as another window manager or the app itself. To keep them from fighting, Tabsome left the window on its own. If you use a window manager, try turning off its rules for \(appName).")
            }
        }
    }

    static let shownNoticesKey = "shownNotices"

    /// A notice the user sees once, ever (PLAN.md §6.2 P4, Stage Manager).
    static func showOnce(_ id: String, title: String, message: String, action: (String, () -> Void)? = nil) {
        let defaults = UserDefaults.standard
        var shown = Set(defaults.stringArray(forKey: shownNoticesKey) ?? [])
        guard !shown.contains(id) else { return }
        shown.insert(id)
        defaults.set(Array(shown), forKey: shownNoticesKey)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let action { alert.addButton(withTitle: action.0) }
        alert.addButton(withTitle: action == nil ? "OK" : "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { action?.1() }
    }

    var needsOnboarding: Bool { !permissions.accessibility || !onboardingCompleted }

    func startIfPermitted() {
        if permissions.accessibility { start() }
    }

    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    private func start() {
        registry.start()
        // After sleep, re-read every app's windows, then re-validate the groups (§5.8).
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.registry.isRunning else { return }
                    FileLog.shared.write("wake")
                    self.registry.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        MainActor.assumeIsolated { self?.groups.revalidateAll() }
                    }
                }
            }
        }
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
        if StageManager.isOn {
            FileLog.shared.write("stage manager is on")
            DispatchQueue.main.async {
                Self.showOnce("stageManager",
                             title: "Stage Manager is on",
                             message: "Stage Manager moves and resizes windows on its own, which conflicts with tabs. Tabs work best with Stage Manager turned off in System Settings › Desktop & Dock.",
                             action: ("Open Desktop & Dock Settings", StageManager.openSettings))
            }
        }
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
