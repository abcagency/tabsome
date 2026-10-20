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

/// Something Tabsome does to another app's window (PLAN.md §6.1 S1: window level only).
enum WindowCommand: Sendable, Equatable {
    /// Size → position → size (PLAN.md §5.4).
    case setFrame(CGRect)
    case setPosition(CGPoint)
    case raise
    /// Presses the window's own close button, so the app can ask to save.
    case close
    case setMinimized(Bool)
}

/// What came back from a command. `frame` is the window's frame read back afterwards (apps
/// like Terminal round what they're given), or nil if it couldn't be read.
struct CommandResult: Sendable, Equatable {
    let ok: Bool
    let frame: CGRect?
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
    /// Runs on the window's app thread; `completion` comes back on the main actor.
    func perform(_ command: WindowCommand, window: CGWindowID, pid: pid_t, completion: (@MainActor (CommandResult) -> Void)?)
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

    func perform(_ command: WindowCommand, window: CGWindowID, pid: pid_t, completion: (@MainActor (CommandResult) -> Void)?) {
        guard let app = apps[pid] else {
            completion?(CommandResult(ok: false, frame: nil))
            return
        }
        app.perform(command, window: window) { result in
            // Through the main run loop in common modes, not the main dispatch queue: Quit waits
            // for these inside a nested run loop, possibly while the main queue is busy (§5.12).
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                MainActor.assumeIsolated { completion?(result) }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }
}
