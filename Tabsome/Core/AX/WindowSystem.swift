import AppKit
import CoreGraphics

/// What Tabsome knows about one window: plain values only, no AX handles, so it can cross
/// threads and be faked in tests.
struct WindowSnapshot: Sendable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    /// Sensitive (PLAN.md §6.1 S4): log only with `privacy: .private`, never to `FileLog`.
    var title: String?
    /// Global top-left-origin coordinates (the same space as CGWindowList bounds).
    var frame: CGRect
    var subrole: String?
    var isStandard: Bool
    var isMinimized: Bool
    var isFullScreen: Bool
    var isMain: Bool
}

/// Everything the window system tells the registry. Delivered on the main thread, in order.
enum WindowEvent: Sendable, Equatable {
    /// The complete current window list of one app (initial scan, or after it recovers).
    case appWindows(pid_t, [WindowSnapshot])
    case windowUpdated(WindowSnapshot)
    case windowDestroyed(pid_t, CGWindowID)
    case mainWindowChanged(pid_t, CGWindowID?)
    /// The app stopped answering within the messaging timeout (true) or answers again (false).
    case appResponsiveness(pid_t, responsive: Bool)
    /// AX calls are failing with "API disabled": the Accessibility permission was revoked.
    case accessibilityDisabled
}

/// The registry's view of the window system (PLAN.md §4). The live implementation is
/// `AXWindowSystem`; tests use a fake.
@MainActor
protocol WindowSystem: AnyObject {
    /// Start delivering events for this app's windows.
    func track(pid: pid_t)
    /// Stop, and release every handle and observer for the app (PLAN.md §6.2 P6).
    func untrack(pid: pid_t)
    func untrackAll()
    var onEvent: ((WindowEvent) -> Void)? { get set }
}

/// Live implementation: one `AXApp` (with its own thread) per tracked app.
@MainActor
final class AXWindowSystem: WindowSystem {
    var onEvent: ((WindowEvent) -> Void)?
    private var apps: [pid_t: AXApp] = [:]

    func track(pid: pid_t) {
        guard apps[pid] == nil else { return }
        apps[pid] = AXApp(pid: pid) { [weak self] event in
            // From the app's AX thread to the main thread, preserving order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onEvent?(event) }
            }
        }
    }

    func untrack(pid: pid_t) {
        apps.removeValue(forKey: pid)?.stop()
    }

    func untrackAll() {
        for app in apps.values { app.stop() }
        apps.removeAll()
    }

    var trackedCount: Int { apps.count }
}
