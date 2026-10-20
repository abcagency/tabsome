import AppKit
import CoreGraphics

/// Phase 2's drag loop (PLAN.md §5.1–5.3): mouse down on an eligible window → its title-bar drag
/// is detected → the target under the cursor is resolved (≤ 30 Hz) → the dwell arms → the
/// highlight shows. Mouse up while armed is where Phase 3 merges.
@MainActor
final class DragCoordinator {
    private let registry: WindowRegistry
    private let monitor = DragMonitor()
    private let highlight = DropHighlightWindow()
    private var dwell = DwellStateMachine()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// One press of the mouse button on a window that could be tabbed.
    private struct Press {
        let window: CGWindowID
        let pid: pid_t
        let downFrame: CGRect
        var dragging = false
        var lastTarget: DropTargetResolver.Target?
    }

    private var press: Press?
    private var lastResolve: TimeInterval = 0
    private var lastCursor = CGPoint.zero
    private var trailingResolve: Timer?
    private var tickTimer: Timer?
    private static let resolveInterval: TimeInterval = 1.0 / 30

    /// Phase 3 replaces this with the merge.
    var onDrop: ((_ dragged: CGWindowID, _ target: CGWindowID) -> Void)?

    init(registry: WindowRegistry) {
        self.registry = registry
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
        press = Press(window: hit.id, pid: hit.pid, downFrame: hit.bounds)
    }

    private func dragged(to point: CGPoint) {
        guard var p = press else { return }
        lastCursor = point
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
                FileLog.shared.write("drag start window=\(p.window)")
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
        perform(dwell.mouseUp())
        FileLog.shared.write("drag end window=\(p.window)")
        endPress(cancel: false)
    }

    private func endPress(cancel: Bool) {
        if cancel { perform(dwell.cancel()) }
        press = nil
        trailingResolve?.invalidate()
        tickTimer?.invalidate()
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
                FileLog.shared.write("drop window=\(dragged) target=\(target) (merge arrives in Phase 3)")
                onDrop?(dragged, target)
            }
        }
    }

    private func showHighlight(on target: CGWindowID) {
        guard let p = press, let frame = p.lastTarget?.frame,
              let targetEntry = registry.windows[target], let draggedEntry = registry.windows[p.window] else { return }
        let tabs = TabLabel.ghostTabs(existing: [targetEntry], adding: draggedEntry)
        highlight.show(targetFrame: frame, above: target, tabs: tabs)
        FileLog.shared.write("armed target=\(target) window=\(p.window)")
    }

    // MARK: Eligibility (S6)

    private func eligible(_ id: CGWindowID) -> Bool {
        guard let entry = registry.windows[id] else { return false }
        return Eligibility.canTab(entry.window, bundleID: entry.app.bundleID)
    }
}
