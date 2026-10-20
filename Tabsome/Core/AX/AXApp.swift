import ApplicationServices
import CoreGraphics
import Foundation

// One of the only two files allowed to call Accessibility APIs (PLAN.md §6.1 S1).
//
// AXApp owns everything AX for one app (PLAN.md §6.2 P1, P6): a dedicated thread with its own
// run loop, the app element, the AXObserver, and every window handle. AX messages are
// synchronous and a hung app blocks the caller, so all calls happen on that thread with a
// 0.5 s timeout; a hung app only stalls its own thread. Results leave as `WindowEvent` values.

nonisolated final class AXApp: @unchecked Sendable {
    // @unchecked: every mutable property below is touched only on `thread`.

    let pid: pid_t
    private let emit: @Sendable (WindowEvent) -> Void
    private let thread: AXThread

    private var appElement: AXUIElement?
    private var observer: AXObserver?
    private var windows: [AXUIElement: AXWindow] = [:]
    private var dirty: Set<CGWindowID> = []
    private var flushScheduled = false
    private var setupAttempts = 0
    private var unresponsive = false
    private var stopped = false

    static let messagingTimeout: Float = 0.5

    init(pid: pid_t, emit: @escaping @Sendable (WindowEvent) -> Void) {
        self.pid = pid
        self.emit = emit
        self.thread = AXThread(name: "com.tabsome.ax.\(pid)")
        thread.start()
        thread.perform { self.setUp() }
    }

    /// Tears down every observer and handle on the AX thread, then ends the thread (P6).
    func stop() {
        thread.perform {
            self.stopped = true
            self.tearDown()
            self.thread.finish()
        }
    }

    // MARK: Commands

    /// Runs a window command on this app's thread (never the main thread, P1).
    func perform(_ command: WindowCommand, window id: CGWindowID, done: @escaping @Sendable (CommandResult) -> Void) {
        thread.perform {
            guard !self.stopped, !self.unresponsive, let window = self.windows.values.first(where: { $0.id == id }) else {
                return done(CommandResult(ok: false, frame: nil))
            }
            let ok: Bool = switch command {
            case .setFrame(let frame): window.setFrame(frame)
            case .setPosition(let point): window.setPosition(point)
            case .raise: window.raise()
            case .close: window.pressClose()
            case .setMinimized(let minimized): window.setMinimized(minimized)
            }
            let frame: CGRect? = if case .success(let s) = window.snapshot() { s.frame } else { nil }
            done(CommandResult(ok: ok, frame: frame))
        }
    }

    // MARK: Setup

    private func setUp() {
        guard !stopped else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        appElement = app

        var obs: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &obs) == .success, let obs else { return retrySetUp() }
        // A just-launched app may not answer AX yet: registration fails until it does.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, refcon)
        if result == .apiDisabled { emit(.accessibilityDisabled); return }
        guard result == .success || result == .notificationAlreadyRegistered else {
            return result == .cannotComplete ? setUpWhenResponsive() : retrySetUp()
        }
        if unresponsive {
            unresponsive = false
            Log.ax.notice("pid \(self.pid) responsive again")
            emit(.appResponsiveness(pid, responsive: true))
        }
        for n in [kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(obs, app, n as CFString, refcon)
        }
        CFRunLoopAddSource(thread.runLoop, AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        rescan()
    }

    /// Timed out: the app is still launching, or it's hung. A few quick retries cover launching;
    /// after that it's marked unresponsive and probed once a second until it answers (P1).
    private func setUpWhenResponsive() {
        setupAttempts += 1
        if setupAttempts <= 3 {
            thread.perform(after: 0.25 * pow(2, Double(setupAttempts - 1))) { self.setUp() }
            return
        }
        if !unresponsive {
            unresponsive = true
            Log.ax.notice("pid \(self.pid) unresponsive during setup (AX timed out)")
            emit(.appResponsiveness(pid, responsive: false))
        }
        thread.perform(after: 1) { self.setUp() }
    }

    /// Other failures (the app doesn't support AX yet, or at all): bounded back-off of
    /// 0.25, 0.5, 1, 2, 4 s, then give up.
    private func retrySetUp() {
        setupAttempts += 1
        guard setupAttempts <= 5 else {
            Log.ax.info("pid \(self.pid) never answered AX; not tracking it")
            return
        }
        let delay = 0.25 * pow(2, Double(setupAttempts - 1))
        thread.perform(after: delay) { self.setUp() }
    }

    private func tearDown() {
        if let obs = observer {
            for (element, _) in windows {
                for n in axWindowNotifications { AXObserverRemoveNotification(obs, element, n as CFString) }
            }
            if let app = appElement {
                for n in [kAXWindowCreatedNotification, kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification] {
                    AXObserverRemoveNotification(obs, app, n as CFString)
                }
            }
            CFRunLoopRemoveSource(thread.runLoop, AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observer = nil
        windows.removeAll()
        dirty.removeAll()
        appElement = nil
    }

    // MARK: Window list

    /// Re-reads the whole window list and reports it.
    private func rescan() {
        guard let app = appElement, !stopped else { return }
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        if err == .cannotComplete { return markUnresponsive() }
        if err == .apiDisabled { return emit(.accessibilityDisabled) }
        let elements = (value as? [AnyObject] ?? []).compactMap { obj -> AXUIElement? in
            CFGetTypeID(obj) == AXUIElementGetTypeID() ? (obj as! AXUIElement) : nil
        }
        // Forget windows that disappeared without a destroyed notification.
        let current = Set(elements)
        for (element, _) in windows where !current.contains(element) { forget(element) }
        var snapshots: [WindowSnapshot] = []
        for element in elements {
            guard let window = windows[element] ?? adopt(element) else { continue }
            if case .success(let s) = window.snapshot() { snapshots.append(s) }
        }
        emit(.appWindows(pid, snapshots))
    }

    /// Starts tracking a window element and registers its notifications.
    @discardableResult
    private func adopt(_ element: AXUIElement) -> AXWindow? {
        if let existing = windows[element] { return existing }
        guard let window = AXWindow(element: element, pid: pid), let obs = observer else { return nil }
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in axWindowNotifications { AXObserverAddNotification(obs, element, n as CFString, refcon) }
        windows[element] = window
        return window
    }

    private func forget(_ element: AXUIElement) {
        guard let window = windows.removeValue(forKey: element) else { return }
        if let obs = observer {
            for n in axWindowNotifications { AXObserverRemoveNotification(obs, element, n as CFString) }
        }
        dirty.remove(window.id)
        emit(.windowDestroyed(pid, window.id))
    }

    // MARK: Notifications (on the AX thread)

    fileprivate func handle(_ notification: String, _ element: AXUIElement) {
        guard !stopped else { return }
        switch notification {
        case kAXWindowCreatedNotification:
            if let window = adopt(element) { markDirty(window.id) }
        case kAXUIElementDestroyedNotification:
            forget(element)
        case kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification:
            let window = windows[element] ?? adopt(element)
            emit(.mainWindowChanged(pid, window?.id))
            if let window { markDirty(window.id) }
        default:
            // Moved, resized, title, (de)miniaturized: coalesce into one read per window per frame,
            // so a live drag doesn't turn into a flood of AX reads (P2, P3).
            if let window = windows[element] { markDirty(window.id) }
        }
    }

    private func markDirty(_ id: CGWindowID) {
        dirty.insert(id)
        guard !flushScheduled else { return }
        flushScheduled = true
        thread.perform(after: 1.0 / 60) { self.flush() }
    }

    private func flush() {
        flushScheduled = false
        guard !stopped, !unresponsive else { return }
        let ids = dirty
        dirty.removeAll()
        for window in windows.values where ids.contains(window.id) {
            switch window.snapshot() {
            case .success(let s): emit(.windowUpdated(s))
            case .failure(.timedOut): return markUnresponsive()
            case .failure(.apiDisabled): return emit(.accessibilityDisabled)
            case .failure(.gone): forget(window.element)
            }
        }
    }

    // MARK: Hung apps (P1)

    /// Stop reading from this app and probe once a second until it answers again.
    private func markUnresponsive() {
        guard !unresponsive else { return }
        unresponsive = true
        Log.ax.notice("pid \(self.pid) unresponsive (AX timed out)")
        emit(.appResponsiveness(pid, responsive: false))
        thread.perform(after: 1) { self.probe() }
    }

    private func probe() {
        guard !stopped, let app = appElement else { return }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &value) == .cannotComplete {
            thread.perform(after: 1) { self.probe() }
            return
        }
        unresponsive = false
        Log.ax.notice("pid \(self.pid) responsive again")
        emit(.appResponsiveness(pid, responsive: true))
        rescan()
    }
}

/// C callback for every AXObserver. Runs on the owning AXApp's thread.
private func axObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<AXApp>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element)
}

/// A thread that runs its own run loop until `finish()`: one per app (P1).
nonisolated final class AXThread: Thread, @unchecked Sendable {
    private var loop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private var shouldExit = false

    init(name: String) {
        super.init()
        self.name = name
        qualityOfService = .userInitiated
    }

    override func start() {
        super.start()
        ready.wait()
    }

    override func main() {
        loop = CFRunLoopGetCurrent()
        // A port keeps the run loop alive while there's nothing else to do; it sleeps, no polling.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !shouldExit {
            CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, true)
        }
    }

    var runLoop: CFRunLoop { loop! }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    /// One-shot, used only for coalescing, back-off, and probing a hung app.
    func perform(after seconds: Double, _ block: @escaping () -> Void) {
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + seconds, 0, 0, 0) { _ in block() }
        CFRunLoopAddTimer(loop, timer, .defaultMode)
    }

    /// Call on this thread: ends the run loop after the current block.
    func finish() {
        shouldExit = true
        CFRunLoopStop(loop)
    }
}
