import AppKit
import CoreGraphics

/// Phase 2's drag loop (PLAN.md §5.1–5.3): mouse down on an eligible window → its title-bar drag
/// is detected → the target under the cursor is resolved (≤ 30 Hz) → the dwell arms → the
/// highlight shows. Mouse up while armed is where Phase 3 merges.
@MainActor
final class DragCoordinator {
    private let registry: WindowRegistry
    private let groups: GroupManager
    private let monitor = DragMonitor()
    private let highlight = DropHighlightWindow()
    private var dwell = DwellStateMachine()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// One press of the mouse button on a window that could be tabbed.
    private struct Press {
        let window: CGWindowID
        let pid: pid_t
        let downFrame: CGRect
        /// The window is a group's active tab: dragging its title bar moves the whole group.
        let movesGroup: Bool
        var dragging = false
        var lastTarget: DropTargetResolver.Target?
    }

    private var press: Press?
    private var lastResolve: TimeInterval = 0
    private var lastCursor = CGPoint.zero
    private var trailingResolve: Timer?
    private var tickTimer: Timer?
    /// The dragged window, captured while armed (§5.9: capture takes 50–140 ms, so it starts
    /// before mouse up). Memory only; dropped with the press (S3).
    private var snapshot: (window: CGWindowID, image: CGImage?)?
    private var snapshotTask: Task<Void, Never>?
    private static let resolveInterval: TimeInterval = 1.0 / 30

    init(registry: WindowRegistry, groups: GroupManager) {
        self.registry = registry
        self.groups = groups
        monitor.onEvent = { [weak self] event, _ in self?.handle(event) }
    }

    func start() { monitor.start() }

    func stop() {
        monitor.stop()
        endPress(cancel: true)
    }

    // MARK: Events

    private func handle(_ event: DragMonitor.Event) {
        switch event {
        case .down(let p): pressed(at: p)
        case .dragged(let p): dragged(to: p)
        case .up: released()
        }
    }

    private func pressed(at point: CGPoint) {
        endPress(cancel: true)
        guard !Eligibility.secureInputActive,
              let hit = ScreenWindows.onScreen().first(where: { $0.layer == 0 && $0.pid != ownPID && $0.bounds.contains(point) }),
              eligible(hit.id) else { return }
        let grouped = groups.group(containing: hit.id) != nil
        // Inactive tabs are hidden behind the active one; nothing to drag there.
        if grouped, !groups.isActiveMember(hit.id) { return }
        press = Press(window: hit.id, pid: hit.pid, downFrame: hit.bounds, movesGroup: grouped)
    }

    private func dragged(to point: CGPoint) {
        guard var p = press else { return }
        lastCursor = point
        // A group's title-bar drag: the strip follows the window server's bounds on every drag
        // event (once per display frame at most), never the sparse AX notifications (§5.6).
        if p.dragging, p.movesGroup {
            if let bounds = ScreenWindows.bounds(of: p.window) { groups.memberDragMoved(p.window, bounds: bounds) }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        // Throttle window-server reads to 30 Hz, with a trailing read so the last position counts.
        guard now - lastResolve >= Self.resolveInterval else {
            scheduleTrailingResolve(at: lastResolve + Self.resolveInterval)
            return
        }
        lastResolve = now
        trailingResolve?.invalidate()

        if !p.dragging {
            guard let current = ScreenWindows.bounds(of: p.window) else { return }
            switch DragClassifier.classify(downFrame: p.downFrame, current: current) {
            case .none: return
            case .resize:
                press = nil // resizing, not a tabbing gesture
                return
            case .drag:
                p.dragging = true
                press = p
                FileLog.shared.write("drag start window=\(p.window)\(p.movesGroup ? " (group)" : "")")
                if p.movesGroup {
                    groups.memberDragMoved(p.window, bounds: current)
                    return
                }
            }
        }
        if Eligibility.secureInputActive {
            perform(dwell.cancel())
            press = nil
            return
        }
        let target = DropTargetResolver.resolve(cursor: point, windows: ScreenWindows.onScreen(), dragged: p.window,
                                                ownPID: ownPID, isEligible: eligible)
        p.lastTarget = target
        press = p
        perform(dwell.update(cursor: point, time: now, target: target?.inMiddle == true ? target?.id : nil))
    }

    private func released() {
        guard let p = press, p.dragging else {
            press = nil
            return
        }
        if p.movesGroup {
            groups.memberDragEnded(p.window)
            FileLog.shared.write("drag end window=\(p.window) (group)")
            return endPress(cancel: false)
        }
        perform(dwell.mouseUp())
        FileLog.shared.write("drag end window=\(p.window)")
        endPress(cancel: false)
    }

    private func endPress(cancel: Bool) {
        if cancel { perform(dwell.cancel()) }
        press = nil
        trailingResolve?.invalidate()
        tickTimer?.invalidate()
        snapshotTask?.cancel()
        snapshotTask = nil
        snapshot = nil
    }

    private func scheduleTrailingResolve(at time: TimeInterval) {
        guard trailingResolve == nil || trailingResolve?.isValid == false else { return }
        let delay = max(0, time - ProcessInfo.processInfo.systemUptime)
        trailingResolve = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dragged(to: self.lastCursor)
            }
        }
    }

    // MARK: Effects

    private func perform(_ effects: [DwellStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .scheduleTick(let at):
                tickTimer?.invalidate()
                tickTimer = Timer.scheduledTimer(withTimeInterval: max(0, at - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.perform(self.dwell.tick(time: ProcessInfo.processInfo.systemUptime))
                    }
                }
            case .showHighlight(let target):
                showHighlight(on: target)
            case .hideHighlight:
                highlight.hide()
                FileLog.shared.write("disarmed")
            case .drop(let target):
                guard let dragged = press?.window else { break }
                FileLog.shared.write("drop window=\(dragged) target=\(target)")
                let image = snapshot?.window == dragged ? snapshot?.image : nil
                groups.merge(dragged: dragged, into: target, dropFrame: ScreenWindows.bounds(of: dragged), snapshot: image)
            }
        }
    }

    private func showHighlight(on target: CGWindowID) {
        guard let p = press, let frame = p.lastTarget?.frame,
              let targetEntry = registry.windows[target], let draggedEntry = registry.windows[p.window] else { return }
        // A grouped target previews its existing tabs, then the new one.
        let existing = groups.group(containing: target).map { $0.members.compactMap { registry.windows[$0] } } ?? [targetEntry]
        let tabs = TabLabel.ghostTabs(existing: existing, adding: draggedEntry)
        highlight.show(targetFrame: frame, above: target, tabs: tabs)
        FileLog.shared.write("armed target=\(target) window=\(p.window)")
        let dragged = p.window
        if snapshot?.window != dragged {
            snapshot = (dragged, nil)
            snapshotTask = Task { @MainActor [weak self] in
                let image = await WindowCapture.capture(dragged)
                guard !Task.isCancelled, self?.snapshot?.window == dragged else { return }
                self?.snapshot = (dragged, image)
            }
        }
    }

    // MARK: Eligibility (S6)

    private func eligible(_ id: CGWindowID) -> Bool {
        guard let entry = registry.windows[id] else { return false }
        // A group's hidden tabs never count; its active tab stands for the group.
        if groups.group(containing: id) != nil, !groups.isActiveMember(id) { return false }
        return Eligibility.canTab(entry.window, bundleID: entry.app.bundleID)
    }
}
