import AppKit
import CoreGraphics

/// The drag loop (PLAN.md §5.1–5.3), shared by three kinds of drag:
/// - a window's title bar: tab it into the target (at the end, or at a strip position);
/// - a group's active window: the strip follows live, and the whole group can merge into another;
/// - a tab torn out of a strip (driven by `GroupManager`): move it to another group or window.
/// The target under the cursor is resolved at most 30 times a second; over a window's middle the
/// dwell arms the highlight, over a strip the insertion marker shows at once.
@MainActor
final class DragCoordinator {
    private let registry: WindowRegistry
    private let groups: GroupManager
    private let monitor = DragMonitor()
    private let highlight = DropHighlightWindow()
    private var dwell = DwellStateMachine()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    fileprivate enum Source: Equatable {
        case window
        /// A group's active window: dragging it moves the group.
        case groupWindow(UUID)
        /// Tabs being torn out of their strip (one, or a selection of `count`).
        case tab(UUID, count: Int)
    }

    private struct Press {
        let window: CGWindowID
        let source: Source
        let downFrame: CGRect
        var dragging = false
        var lastTarget: DropTargetResolver.Resolved?
    }

    private var press: Press?
    private var lastResolve: TimeInterval = 0
    private var lastCursor = CGPoint.zero
    private var trailingResolve: Timer?
    private var tickTimer: Timer?
    /// The dragged window, captured once armed (§5.9: capture takes 50–140 ms, so it starts
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

    // MARK: Tab drags (from GroupManager)

    func tabDragBegan(window: CGWindowID, group: UUID, count: Int = 1) {
        endPress(cancel: true)
        press = Press(window: window, source: .tab(group, count: count), downFrame: .zero, dragging: true)
    }

    func tabDragMoved(to point: CGPoint) {
        guard press?.source.isTab == true else { return }
        dragged(to: point)
    }

    /// Where the tab was dropped: another group's strip, a window's middle (armed), or nowhere.
    func tabDragEnded() -> DwellStateMachine.Effect? {
        guard let p = press, p.source.isTab else { return nil }
        let effects = dwell.mouseUp()
        perform(effects, dropping: false) // hide the highlight / marker; the caller does the drop
        endPress(cancel: false)
        return effects.first { if case .drop = $0 { true } else if case .dropOnStrip = $0 { true } else { false } }
    }

    // MARK: Mouse events

    private func handle(_ event: DragMonitor.Event) {
        switch event {
        case .down(let p): pressed(at: p)
        case .dragged(let p): if press?.source.isTab != true { dragged(to: p) }
        case .up: if press?.source.isTab != true { released() }
        }
    }

    private func pressed(at point: CGPoint) {
        endPress(cancel: true)
        guard !Eligibility.secureInputActive,
              let hit = ScreenWindows.onScreen().first(where: { $0.layer == 0 && $0.pid != ownPID && $0.bounds.contains(point) }),
              let entry = registry.windows[hit.id], Eligibility.canTab(entry.window, bundleID: entry.app.bundleID) else { return }
        if let g = groups.group(containing: hit.id) {
            // Inactive tabs are hidden behind the active one; nothing to drag there.
            guard g.activeID == hit.id else { return }
            press = Press(window: hit.id, source: .groupWindow(g.id), downFrame: hit.bounds)
        } else {
            press = Press(window: hit.id, source: .window, downFrame: hit.bounds)
        }
    }

    private func dragged(to point: CGPoint) {
        guard var p = press else { return }
        lastCursor = point
        // A group's title-bar drag: the strip follows the window server's bounds on every drag
        // event, never the sparse AX notifications (§5.6). Targeting below is throttled.
        if p.dragging, case .groupWindow = p.source, let bounds = ScreenWindows.bounds(of: p.window) {
            groups.memberDragMoved(p.window, bounds: bounds)
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
                FileLog.shared.write("drag start window=\(p.window)\(p.source == .window ? "" : " (group)")")
                if case .groupWindow = p.source { groups.memberDragMoved(p.window, bounds: current) }
            }
        }
        if Eligibility.secureInputActive {
            perform(dwell.cancel())
            press = nil
            return
        }
        let resolved = DropTargetResolver.resolve(cursor: point, windows: ScreenWindows.onScreen(), dragged: p.window, ownPID: ownPID,
                                                  strip: { [groups] w in groups.stripHit(panel: w.id, cursor: point, excluding: p.source.group, incoming: incoming(p)) },
                                                  isEligible: { id in self.eligibleTarget(id, for: p) })
        p.lastTarget = resolved
        press = p
        perform(dwell.update(cursor: point, time: now, target: resolved?.dwellTarget))
    }

    private func released() {
        guard let p = press, p.dragging else {
            press = nil
            return
        }
        let effects = dwell.mouseUp()
        let dropped = effects.contains { if case .drop = $0 { true } else if case .dropOnStrip = $0 { true } else { false } }
        perform(effects)
        if case .groupWindow = p.source, !dropped { groups.memberDragEnded(p.window) }
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

    private func perform(_ effects: [DwellStateMachine.Effect], dropping: Bool = true) {
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
            case .showInsertion(let target, let index):
                groups.showInsertion(target: target, index: index)
                captureDragged()
            case .hideInsertion(let target):
                groups.hideInsertion(target: target)
            case .drop(let target):
                guard dropping, let p = press, !p.source.isTab else { break }
                FileLog.shared.write("drop window=\(p.window) target=\(target)")
                drop(p, into: target, at: nil)
            case .dropOnStrip(let target, let index):
                guard dropping, let p = press, !p.source.isTab else { break }
                FileLog.shared.write("drop window=\(p.window) on strip target=\(target) index=\(index)")
                drop(p, into: target, at: index)
            }
        }
    }

    private func drop(_ p: Press, into target: CGWindowID, at index: Int?) {
        let image = snapshot?.window == p.window ? snapshot?.image : nil
        let frame = ScreenWindows.bounds(of: p.window)
        if case .groupWindow(let gid) = p.source {
            groups.mergeGroup(gid, into: target, at: index, dropFrame: frame, snapshot: image)
        } else {
            groups.merge(dragged: p.window, into: target, at: index, dropFrame: frame, snapshot: image)
        }
    }

    private func showHighlight(on target: CGWindowID) {
        guard let p = press, case .window(let t) = p.lastTarget, t.id == target,
              let targetEntry = registry.windows[target] else { return }
        // A grouped target previews its existing tabs, then the new ones at the end.
        let existing = groups.group(containing: target).map { $0.members.compactMap { registry.windows[$0] } } ?? [targetEntry]
        let adding = (p.source.group.flatMap { gid in groups.groups[gid]?.members } ?? [p.window]).compactMap { registry.windows[$0] }
        highlight.show(targetFrame: t.frame, above: target, tabs: TabLabel.ghostTabs(existing: existing, adding: adding, names: registry.customNames),
                       placement: groups.placement)
        FileLog.shared.write("armed target=\(target) window=\(p.window)")
        captureDragged()
    }

    /// Starts the dragged window's snapshot as soon as a drop is likely.
    private func captureDragged() {
        guard let p = press, !p.source.isTab, snapshot?.window != p.window else { return }
        let dragged = p.window
        snapshot = (dragged, nil)
        snapshotTask = Task { @MainActor [weak self] in
            let image = await WindowCapture.capture(dragged)
            guard !Task.isCancelled, self?.snapshot?.window == dragged else { return }
            self?.snapshot = (dragged, image)
        }
    }

    // MARK: Eligibility (S6, §1)

    /// How many tabs this drag would add to a target group.
    private func incoming(_ p: Press) -> Int {
        switch p.source {
        case .groupWindow(let gid): return groups.groups[gid]?.count ?? 1
        case .tab(_, let count): return count
        case .window: return 1
        }
    }

    private func eligibleTarget(_ id: CGWindowID, for p: Press) -> Bool {
        guard let entry = registry.windows[id], Eligibility.canTab(entry.window, bundleID: entry.app.bundleID) else { return false }
        guard let g = groups.group(containing: id) else { return true }
        // A group's hidden tabs never count; its active tab stands for the group. Never the
        // dragged tab's own group, and never a full one (the quiet 50-tab limit).
        return g.activeID == id && g.id != p.source.group && g.canAccept(incoming(p))
    }
}

private extension DragCoordinator.Source {
    var isTab: Bool { if case .tab = self { true } else { false } }
    var group: UUID? {
        switch self {
        case .window: nil
        case .groupWindow(let g), .tab(let g, _): g
        }
    }
}
