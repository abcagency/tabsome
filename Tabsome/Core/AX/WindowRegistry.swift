import AppKit
import CoreGraphics

/// Live map of CGWindowID → window for every regular app (PLAN.md §4). Fed only by
/// `WindowEvent`s, so it never touches AX itself and can be tested with a fake `WindowSystem`.
@MainActor
@Observable
final class WindowRegistry {
    struct AppInfo: Equatable {
        let pid: pid_t
        let name: String
        let bundleID: String?
    }

    struct Entry: Identifiable, Equatable {
        var window: WindowSnapshot
        let app: AppInfo
        var id: CGWindowID { window.id }
    }

    private(set) var windows: [CGWindowID: Entry] = [:]
    private(set) var apps: [pid_t: AppInfo] = [:]
    private(set) var mainWindow: [pid_t: CGWindowID] = [:]
    private(set) var unresponsive: Set<pid_t> = []
    private(set) var isRunning = false

    /// Called when AX reports the API disabled (permission revoked mid-session).
    @ObservationIgnored var onAccessibilityDisabled: (() -> Void)?

    @ObservationIgnored private let system: WindowSystem
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(system: WindowSystem) {
        self.system = system
        system.onEvent = { [weak self] event in self?.apply(event) }
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.track(app) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self?.untrack(pid: pid) }
            },
        ]
        for app in NSWorkspace.shared.runningApplications { track(app) }
        Log.registry.info("registry started, \(self.apps.count) apps")
        FileLog.shared.write("registry started apps=\(apps.count)")
    }

    /// Stops all tracking and releases every AX handle (permission revoked, or quitting).
    func stop() {
        guard isRunning else { return }
        isRunning = false
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        system.untrackAll()
        windows.removeAll()
        apps.removeAll()
        mainWindow.removeAll()
        unresponsive.removeAll()
        FileLog.shared.write("registry stopped")
    }

    private func track(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        track(AppInfo(pid: app.processIdentifier, name: app.localizedName ?? "?", bundleID: app.bundleIdentifier))
    }

    /// Also the entry point for tests.
    func track(_ info: AppInfo) {
        guard info.pid != ownPID, apps[info.pid] == nil else { return }
        apps[info.pid] = info
        system.track(pid: info.pid)
    }

    func untrack(pid: pid_t) {
        guard apps.removeValue(forKey: pid) != nil else { return }
        system.untrack(pid: pid)
        windows = windows.filter { $0.value.app.pid != pid }
        mainWindow[pid] = nil
        unresponsive.remove(pid)
    }

    // MARK: Events

    func apply(_ event: WindowEvent) {
        switch event {
        case .appWindows(let pid, let snapshots):
            guard let app = apps[pid] else { return }
            windows = windows.filter { $0.value.app.pid != pid }
            for s in snapshots { windows[s.id] = Entry(window: s, app: app) }
            if let main = snapshots.first(where: \.isMain) { mainWindow[pid] = main.id }
        case .windowUpdated(let s):
            guard let app = apps[s.pid] else { return }
            windows[s.id] = Entry(window: s, app: app)
        case .windowDestroyed(let pid, let id):
            windows[id] = nil
            if mainWindow[pid] == id { mainWindow[pid] = nil }
        case .mainWindowChanged(let pid, let id):
            guard apps[pid] != nil else { return }
            mainWindow[pid] = id
        case .appResponsiveness(let pid, let responsive):
            if responsive { unresponsive.remove(pid) } else { unresponsive.insert(pid) }
            FileLog.shared.write("pid \(pid) responsive=\(responsive)")
        case .accessibilityDisabled:
            onAccessibilityDisabled?()
        }
    }

    /// Windows of one app, front-most order unknown (z-order comes from CGWindowList when needed).
    func windows(of pid: pid_t) -> [Entry] {
        windows.values.filter { $0.app.pid == pid }.sorted { $0.id < $1.id }
    }
}
