import AppKit
import CoreGraphics

/// Owns every group (PLAN.md §4): merge, switch, close, dissolve, minimize, fill, tear-out,
/// move/resize sync, and the quit restore. It talks to other apps only through `WindowSystem`
/// commands, which run on each app's AX thread.
@MainActor
@Observable
final class GroupManager {
    private(set) var groups: [UUID: TabGroup] = [:] {
        didSet { scheduleRecoverySave() }
    }

    @ObservationIgnored private var groupOf: [CGWindowID: UUID] = [:]
    @ObservationIgnored private var strips: [UUID: TabBarWindow] = [:]
    @ObservationIgnored private var expected = ExpectedFrames()
    @ObservationIgnored private var fights = FightDetector()
    /// A member was taken out of its group because something kept moving it back (P4):
    /// the app's name and bundle ID, for a one-time notice.
    @ObservationIgnored var onFight: ((_ appName: String, _ bundleID: String?) -> Void)?
    @ObservationIgnored private var resyncTimers: [UUID: Timer] = [:]
    @ObservationIgnored private var liveDrag: (group: UUID, startContent: CGRect)?
    @ObservationIgnored private var stripDrag: (group: UUID, startContent: CGRect, startMouse: CGPoint, inFlight: Bool, pending: CGPoint?)?
    /// Tabs being torn out of a strip: the grabbed one (its ghost follows the cursor) and any
    /// others selected with it, in strip order.
    @ObservationIgnored private var tearOff: (windows: [CGWindowID], window: CGWindowID, group: UUID, proxy: WindowProxy?, size: CGSize)?
    /// Groups whose background tabs are tucked away while the group moves or resizes.
    @ObservationIgnored private var tucked: Set<UUID> = []
    /// What each member did the last time it was asked for its group's frame (§5.5).
    @ObservationIgnored private var lastFit: [CGWindowID: (requested: CGSize, landed: CGSize)] = [:]
    /// Background tabs waiting in a corner because they'd show around the active one (§5.5).
    @ObservationIgnored private(set) var misfitParked: Set<CGWindowID> = []
    /// Groups Tabsome is moving windows in (a merge, a new group, Fill, a placement change):
    /// frame reports from them in this window aren't the user moving the group (see `settleCheck`).
    @ObservationIgnored private var settlingUntil: [UUID: TimeInterval] = [:]
    @ObservationIgnored private var settleTimers: [UUID: Timer] = [:]
    /// How long after Tabsome moves a group's windows their reports count as part of that move.
    @ObservationIgnored var settleDuration: TimeInterval = 1.0
    @ObservationIgnored private var workspaceObserver: NSObjectProtocol?
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var stripCheck: Timer?
    /// Apps Tabsome itself just activated: their focus events aren't the user switching tabs.
    @ObservationIgnored private var ownActivation: [pid_t: TimeInterval] = [:]
    @ObservationIgnored private let system: WindowSystem
    @ObservationIgnored private let registry: WindowRegistry
    /// Off in tests; proxies need a window server.
    @ObservationIgnored var animates = true
    /// The window server's current bounds for a window (replaced in tests).
    @ObservationIgnored var windowBounds: (CGWindowID) -> CGRect? = { ScreenWindows.bounds(of: $0) }
    /// The windows on the current Space(s), not minimized or hidden (replaced in tests).
    @ObservationIgnored var onScreenWindows: () -> Set<CGWindowID> = { Set(ScreenWindows.onScreen().map(\.id)) }
    /// Every screen's usable area (replaced in tests).
    @ObservationIgnored var usableAreas: () -> [CGRect] = { NSScreen.screens.map { ScreenGeometry.cgRect(fromAppKit: $0.visibleFrame) } }
    /// The usable area (`NSScreen.visibleFrame`) of the screen holding a rect (replaced in tests).
    @ObservationIgnored var usableArea: (CGRect) -> CGRect = { rect in
        let screen = NSScreen.screens.first { ScreenGeometry.cgRect(fromAppKit: $0.frame).contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.screens.first
        return screen.map { ScreenGeometry.cgRect(fromAppKit: $0.visibleFrame) } ?? rect
    }
    /// The group whose active window belongs to the frontmost app: the shortcuts act on it (§5.7).
    @ObservationIgnored private(set) var focusedGroup: UUID?
    @ObservationIgnored var onFocusedGroupChanged: ((UUID?) -> Void)?
    /// Asked before the red button closes every tab (PLAN.md §5.11); returns false to cancel.
    @ObservationIgnored var confirmCloseAll: ((_ count: Int) -> Bool)?
    /// Saves the crash-recovery state (§5.12, P7) shortly after groups change. Nil in tests.
    @ObservationIgnored var onRecoveryStateChanged: ((RecoveryState) -> Void)?
    @ObservationIgnored private var recoverySave: Timer?
    /// A recovery waiting for its windows to show up in the registry.
    @ObservationIgnored private var pendingRecovery: (state: RecoveryState, done: () -> Void)?

    init(registry: WindowRegistry, system: WindowSystem) {
        self.registry = registry
        self.system = system
        registry.onWindowUpdated = { [weak self] old, new in
            self?.windowUpdated(old: old, new: new)
            self?.recoverIfReady()
        }
        registry.onWindowRemoved = { [weak self] id, _ in self?.windowRemoved(id) }
        registry.onMainWindowChanged = { [weak self] pid, id in self?.mainWindowChanged(pid: pid, id: id) }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.appActivated(pid) } }
        }
        // §5.8: the strip follows its window across Spaces and hides with its app; a display
        // change re-validates every group.
        let center = NSWorkspace.shared.notificationCenter
        let stripEvents: [Notification.Name] = [NSWorkspace.activeSpaceDidChangeNotification,
                                                NSWorkspace.didHideApplicationNotification,
                                                NSWorkspace.didUnhideApplicationNotification]
        systemObservers = stripEvents.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleStripCheck() }
            }
        }
        systemObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revalidateScreens() }
        })
    }

    func group(containing id: CGWindowID) -> TabGroup? { groupOf[id].flatMap { groups[$0] } }
    func isActiveMember(_ id: CGWindowID) -> Bool { group(containing: id)?.activeID == id }

    // MARK: Merge (PLAN.md §5.4)

    /// Tabs `dragged` into `target`'s window (or `target`'s group), at the end or at a strip
    /// position. `dropFrame` is where the dragged window was let go; `snapshot` was captured
    /// during the dwell (§5.9).
    func merge(dragged d: CGWindowID, into t: CGWindowID, at index: Int? = nil, dropFrame: CGRect?, snapshot: CGImage?) {
        guard groupOf[d] == nil else { return }
        absorb([d], active: d, into: t, at: index, dropFrame: dropFrame, proxy: makeProxy(for: d, image: snapshot, at: dropFrame))
    }

    /// A whole group dragged by its active window's title bar onto another window or group:
    /// all its tabs join, in order, and its active tab stays active (§7 Phase 4).
    func mergeGroup(_ source: UUID, into t: CGWindowID, at index: Int? = nil, dropFrame: CGRect?, snapshot: CGImage?) {
        guard let g = groups[source], groupOf[t] != source else { return }
        liveDrag = nil
        let members = g.members, active = g.activeID
        if !canAbsorb(members.count, into: t) { return memberDragEnded(active) }
        dropGroup(source)
        absorb(members, active: active, into: t, at: index, dropFrame: dropFrame, proxy: makeProxy(for: active, image: snapshot, at: dropFrame))
    }

    /// Adds `windows` to `t`'s group (or forms one with `t`), activating `active`. The active
    /// window's proxy springs from where it was to the group frame while the real windows move
    /// into place behind the cover, the window being tabbed into (§5.4, §5.9).
    private func absorb(_ windows: [CGWindowID], active: CGWindowID, into t: CGWindowID, at index: Int?,
                        dropFrame: CGRect?, proxy: WindowProxy?) {
        guard !windows.contains(t), let tEntry = registry.windows[t], windows.allSatisfy({ registry.windows[$0] != nil }),
              canAbsorb(windows.count, into: t) else { proxy?.dismiss(); return }
        let cover: CGWindowID
        var group: TabGroup
        if let gid = groupOf[t], var existing = groups[gid] {
            cover = existing.activeID
            existing.insert(windows, at: index)
            existing.activate(active)
            group = existing
        } else {
            cover = t
            let outer = windowBounds( t) ?? tEntry.window.frame
            group = TabGroup(members: [t], active: t, content: StripLayout.frames(outer: outer, placement: placement).content, placement: placement)
            group.insert(windows, at: index)
            group.activate(active)
            groupOf[t] = group.id
        }
        for w in windows { groupOf[w] = group.id }
        groups[group.id] = group
        let gid = group.id
        markSettling(gid)
        FileLog.shared.write("merge windows=\(windows.count) into=\(t) group=\(gid.uuidString.prefix(8)) tabs=\(group.count)")

        activateWindow(cover) {
            self.syncMembers(of: gid, reconcile: true) {
                guard let g = self.groups[gid] else { return }
                let strip = self.strip(for: g)
                strip.place(content: g.content, above: cover)
                strip.show()
                guard let proxy else {
                    self.activateWindow(active)
                    return self.scheduleSettleCheck(gid)
                }
                Task { @MainActor in
                    await proxy.spring(to: g.content)
                    self.activateWindow(active)
                    self.scheduleSettleCheck(gid)
                    if let final = await WindowCapture.capture(active) { proxy.crossfade(to: final) }
                    await proxy.fadeOut()
                }
            }
        }
    }

    private func canAbsorb(_ count: Int, into t: CGWindowID) -> Bool {
        group(containing: t)?.canAccept(count) ?? (count + 1 <= TabGroup.maxTabs)
    }

    private func makeProxy(for id: CGWindowID, image: CGImage?, at frame: CGRect?) -> WindowProxy? {
        guard animates, !Motion.reduced, let entry = registry.windows[id] else { return nil }
        let from = frame ?? entry.window.frame
        let proxy = WindowProxy(image: image, appPID: entry.app.pid, appName: entry.app.name, on: from)
        proxy.show(at: from)
        return proxy
    }

    /// Forgets a group whose tabs are all moving elsewhere (no dissolve: nothing grows back).
    private func dropGroup(_ gid: UUID) {
        guard let g = groups.removeValue(forKey: gid) else { return }
        for id in g.members where groupOf[id] == gid { groupOf[id] = nil }
        resyncTimers.removeValue(forKey: gid)?.invalidate()
        strips.removeValue(forKey: gid)?.dismiss()
        tucked.remove(gid)
        settleTimers.removeValue(forKey: gid)?.invalidate()
        settlingUntil[gid] = nil
    }

    /// Where strips go (Settings › Tabs › Tab position, PLAN.md §5.6).
    @ObservationIgnored private(set) var placement: TabPlacement = .top

    /// Changing placement re-lays out every live group right away: the outer frame stays put,
    /// the old side's strip space goes back, the new side's is taken, and each strip is rebuilt.
    func setPlacement(_ new: TabPlacement) {
        guard new != placement else { return }
        placement = new
        for (gid, var g) in groups {
            let outer = g.outer
            g.placement = new
            g.content = StripLayout.frames(outer: outer, placement: new).content
            groups[gid] = g
            guard let strip = strips[gid] else { continue }
            strip.placement = new
            if !g.isMinimized { strip.place(content: g.content, above: g.activeID) }
            markSettling(gid)
            syncMembers(of: gid, reconcile: true) { self.scheduleSettleCheck(gid) }
        }
    }

    /// For the drag coordinator: a group's strip under the cursor and where a drop would land.
    func stripHit(panel: CGWindowID, cursor: CGPoint, excluding: UUID?, incoming: Int) -> DropTargetResolver.StripHit? {
        guard let (gid, strip) = strips.first(where: { $0.value.windowNumber == panel }), gid != excluding,
              let g = groups[gid], !g.isMinimized, g.canAccept(incoming), let index = strip.insertIndex(at: cursor) else { return nil }
        return .init(target: g.activeID, index: index)
    }

    func showInsertion(target: CGWindowID, index: Int) {
        guard let gid = groupOf[target] else { return }
        strips[gid]?.showInsertion(at: index)
    }

    func hideInsertion(target: CGWindowID) {
        guard let gid = groupOf[target] else { return }
        strips[gid]?.showInsertion(at: nil)
    }

    /// The drag coordinator, for tabs torn out of a strip (targets: another strip, a window's middle).
    @ObservationIgnored weak var targeting: DragCoordinator?

    // MARK: Tabs

    /// Click a tab: raise that window, activate its app, and put the strip above it (§5.7).
    func activate(_ id: CGWindowID) {
        guard let gid = groupOf[id], var g = groups[gid] else { return }
        g.activate(id)
        groups[gid] = g
        refreshStrip(gid)
        bringBack(id, in: g) { self.activateWindow(id) { self.conceal(gid) } }
    }

    /// × or middle-click: the app closes the window itself (and may ask to save). The tab goes
    /// away when the window is destroyed (§5.7, §5.8).
    func close(_ id: CGWindowID) {
        guard let entry = registry.windows[id] else { return }
        system.perform(.close, window: id, pid: entry.app.pid, completion: nil)
    }

    /// Red button: close every tab, after asking (§5.11).
    func closeAll(_ gid: UUID) {
        guard let g = groups[gid] else { return }
        if let confirm = confirmCloseAll, !confirm(g.count) { return }
        for id in g.members { close(id) }
    }

    /// Yellow button: one Dock item. Only the active window is minimized; the others are parked
    /// in the screen corner and the strip is hidden (§5.11).
    func minimize(_ gid: UUID) {
        guard var g = groups[gid], !g.isMinimized else { return }
        g.isMinimized = true
        groups[gid] = g
        strips[gid]?.hide()
        for id in g.inactive { park(id, from: g) }
        command(.setMinimized(true), g.activeID)
        FileLog.shared.write("minimize group=\(gid.uuidString.prefix(8))")
    }

    private func restoreFromMinimize(_ gid: UUID) {
        guard var g = groups[gid], g.isMinimized else { return }
        g.isMinimized = false
        groups[gid] = g
        syncMembers(of: gid, reconcile: false) {
            guard let g = self.groups[gid] else { return }
            self.strips[gid]?.place(content: g.content, above: g.activeID)
            self.strips[gid]?.show()
        }
        FileLog.shared.write("restore group=\(gid.uuidString.prefix(8))")
    }

    /// Green button: fill the usable screen area, or go back (§5.11). Phase 4 animates presets.
    func toggleFill(_ gid: UUID) {
        guard var g = groups[gid] else { return }
        let visible = visibleFrame(containing: g.outer)
        let next = GroupGeometry.fillToggle(outer: g.outer, previous: g.previousOuter, visibleFrame: visible)
        g.previousOuter = next.previous
        g.content = StripLayout.frames(outer: next.outer, placement: g.placement).content
        groups[gid] = g
        markSettling(gid)
        strips[gid]?.place(content: g.content, above: g.activeID)
        syncMembers(of: gid, reconcile: true, activeFirst: true) { self.scheduleSettleCheck(gid) }
    }

    // MARK: Tear-out (§5.7)

    func tearOffBegan(_ id: CGWindowID, cursor: CGPoint) { tearOffBegan([id], grabbed: id, cursor: cursor) }

    /// `ids` are the selected tabs (just `grabbed` unless several were selected), in strip order.
    func tearOffBegan(_ ids: [CGWindowID], grabbed id: CGWindowID, cursor: CGPoint) {
        guard let gid = groupOf[id], let g = groups[gid], let entry = registry.windows[id] else { return }
        let windows = ids.filter { groupOf[$0] == gid }
        let frame = tearOffFrame(cursor: cursor, size: g.content.size)
        let proxy = animates ? WindowProxy(image: nil, appPID: entry.app.pid, appName: entry.app.name, on: frame) : nil
        proxy?.show(at: frame, lifted: true)
        tearOff = (windows.isEmpty ? [id] : windows, id, gid, proxy, g.content.size)
        targeting?.tabDragBegan(window: id, group: gid, count: max(1, windows.count))
        Task { @MainActor in
            if let image = await WindowCapture.capture(id), self.tearOff?.window == id { proxy?.setImage(image) }
        }
    }

    func tearOffMoved(cursor: CGPoint) {
        guard let t = tearOff else { return }
        t.proxy?.move(to: tearOffFrame(cursor: cursor, size: t.size))
        targeting?.tabDragMoved(to: cursor)
    }

    /// Let go. Over another group's strip, the tab moves there at that position; over a window's
    /// middle after the pause, it tabs with that window; anywhere else it leaves the group where
    /// the ghost is, as a normal window at the group's size (§5.7). A group left with one window
    /// dissolves.
    func tearOffEnded(cursor: CGPoint) {
        guard let t = tearOff else { return }
        tearOff = nil
        let frame = tearOffFrame(cursor: cursor, size: t.size)
        switch targeting?.tabDragEnded() {
        case .drop(let target)?:
            return moveTabs(t.windows, active: t.window, into: target, at: nil, from: frame, proxy: t.proxy)
        case .dropOnStrip(let target, let index)?:
            return moveTabs(t.windows, active: t.window, into: target, at: index, from: frame, proxy: t.proxy)
        default:
            break
        }
        // Several tabs dropped in empty space become a group of their own there.
        if t.windows.count > 1 { return formGroup(t.windows, active: t.window, content: frame, proxy: t.proxy) }
        FileLog.shared.write("tear out window=\(t.window)")
        removeMember(t.window, closing: false)
        setFrame(t.window, frame) { landed in
            self.activateWindow(t.window)
            guard let proxy = t.proxy else { return }
            Task { @MainActor in
                if let landed { await proxy.spring(to: landed) }
                await proxy.fadeOut()
            }
        }
    }

    func tearOffCancelled() {
        guard let t = tearOff else { return }
        tearOff = nil
        _ = targeting?.tabDragEnded()
        Task { @MainActor in await t.proxy?.fadeOut() }
    }

    /// A tab leaves its group for another window or group (dragged there, or picked from "+").
    private func moveTab(_ id: CGWindowID, into target: CGWindowID, at index: Int?, from frame: CGRect, proxy: WindowProxy?) {
        moveTabs([id], active: id, into: target, at: index, from: frame, proxy: proxy)
    }

    /// Several tabs (a selection) move together, in order; `active` becomes the active tab.
    private func moveTabs(_ ids: [CGWindowID], active: CGWindowID, into target: CGWindowID, at index: Int?,
                          from frame: CGRect, proxy: WindowProxy?) {
        guard !ids.contains(target), groupOf[target] == nil || groupOf[target] != groupOf[active] || groupOf[active] == nil,
              canAbsorb(ids.count, into: target) else {
            proxy?.dismiss()
            return
        }
        for id in ids { removeMember(id, closing: false) }
        absorb(ids, active: active, into: target, at: index, dropFrame: frame, proxy: proxy)
    }

    /// Selected tabs dropped in empty space, or "Move N Tabs to New Window": they leave their group
    /// and become a group of their own at `content` (§5.7).
    private func formGroup(_ ids: [CGWindowID], active: CGWindowID, content: CGRect, proxy: WindowProxy?) {
        for id in ids { removeMember(id, closing: false) }
        let members = ids.filter { registry.windows[$0] != nil && groupOf[$0] == nil }
        guard members.count > 1, members.contains(active) else {
            proxy?.dismiss()
            if let only = members.first { setFrame(only, content) { _ in self.activateWindow(only) } }
            return
        }
        let group = TabGroup(members: members, active: active, content: content, placement: placement)
        for id in members { groupOf[id] = group.id }
        groups[group.id] = group
        let gid = group.id
        markSettling(gid)
        FileLog.shared.write("new group from tabs=\(members.count) group=\(gid.uuidString.prefix(8))")
        syncMembers(of: gid, reconcile: true) {
            guard let g = self.groups[gid] else { return }
            let strip = self.strip(for: g)
            self.activateWindow(active) {
                strip.place(content: g.content, above: active)
                strip.show()
                self.scheduleSettleCheck(gid)
            }
            guard let proxy else { return }
            Task { @MainActor in
                await proxy.spring(to: g.content)
                await proxy.fadeOut()
            }
        }
    }

    // MARK: Strip menus and buttons (§5.6, §5.7)

    /// Drag a tab sideways: it ends up at `index`.
    func reorder(_ id: CGWindowID, to index: Int) {
        guard let gid = groupOf[id], var g = groups[gid] else { return }
        g.move(id, to: index)
        groups[gid] = g
        refreshStrip(gid)
    }

    func closeTabs(_ ids: [CGWindowID]) {
        for id in ids { close(id) }
    }

    /// "Move N Tabs to New Window": a single tab becomes a normal window; several become a group.
    func moveToNewWindow(_ ids: [CGWindowID], active: CGWindowID) {
        guard ids.count > 1, let g = group(containing: active) else { return moveToNewWindow(active) }
        formGroup(ids, active: active, content: g.content.offsetBy(dx: 22, dy: 22), proxy: nil)
    }

    func closeOthers(_ id: CGWindowID) {
        guard let g = group(containing: id) else { return }
        for other in g.others(than: id) { close(other) }
    }

    func closeToTheRight(_ id: CGWindowID) {
        guard let g = group(containing: id) else { return }
        for other in g.toTheRight(of: id) { close(other) }
    }

    /// Move Tab to New Window: out of the group in place, cascaded so it's visible (§5.7).
    func moveToNewWindow(_ id: CGWindowID) {
        guard let g = group(containing: id) else { return }
        let frame = g.outer.offsetBy(dx: 22, dy: 22)
        removeMember(id, closing: false)
        setFrame(id, frame) { _ in self.activateWindow(id) }
    }

    /// "+": windows that could join this group (§5.6): eligible, not already in it.
    func addCandidates(for gid: UUID) -> [AddCandidate] {
        guard let g = groups[gid], g.canAccept(1) else { return [] }
        return registry.windows.values
            .filter { !g.contains($0.id) && Eligibility.canTab($0.window, bundleID: $0.app.bundleID) }
            .sorted { ($0.app.name, $0.window.title ?? "") < ($1.app.name, $1.window.title ?? "") }
            .map { AddCandidate(id: $0.id, pid: $0.app.pid, appName: $0.app.name, title: $0.window.title) }
    }

    func add(_ id: CGWindowID, to gid: UUID) {
        guard let g = groups[gid], !g.contains(id), let entry = registry.windows[id] else { return }
        let from = windowBounds( id) ?? entry.window.frame
        Task { @MainActor in
            let image = await WindowCapture.capture(id)
            let proxy = self.makeProxy(for: id, image: image, at: from)
            if self.groupOf[id] != nil {
                self.moveTab(id, into: g.activeID, at: nil, from: from, proxy: proxy)
            } else {
                self.absorb([id], active: id, into: g.activeID, at: nil, dropFrame: from, proxy: proxy)
            }
        }
    }

    /// Double-click empty strip area: what a title-bar double-click does on this Mac (§5.7),
    /// per System Settings › Desktop & Dock.
    // MARK: Renaming (§5.10)

    /// Saves a tab's name (trimmed, at most 60 characters; empty resets it), then gives the keyboard
    /// back to the tab's window.
    func rename(_ id: CGWindowID, to name: String?, refocus: Bool = true) {
        registry.setCustomName(name, for: id)
        if let gid = groupOf[id] { refreshStrip(gid) }
        if refocus { self.refocus(id) }
    }

    /// The rename field had the keyboard; return it to the group's active window.
    func refocus(_ id: CGWindowID) {
        guard let g = group(containing: id) else { return }
        activateWindow(g.activeID)
    }

    /// ⌃⌥R and the right-click menu: start renaming a tab in its strip.
    func beginRename(_ id: CGWindowID) {
        guard let gid = groupOf[id] else { return }
        strips[gid]?.beginRename(id)
    }

    // MARK: Shortcuts (§5.7)

    private func updateFocus() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focused = groups.values.first { !$0.isMinimized && registry.windows[$0.activeID]?.app.pid == front }?.id
        guard focused != focusedGroup else { return }
        focusedGroup = focused
        onFocusedGroupChanged?(focused)
    }

    /// ⌃⌥Tab / ⌃⌥⇧Tab wrap around; ⌃⌥1–8 go to that tab; ⌃⌥9 is the last tab; ⌃⌥W closes the
    /// active tab; ⌃⌥⇧N moves it out; ⌃⌥R renames it.
    func perform(_ action: HotKeys.Action) {
        updateFocus()
        guard let gid = focusedGroup, let g = groups[gid] else { return }
        let i = g.activeIndex, n = g.count
        switch action {
        case .next: activate(g.members[(i + 1) % n])
        case .previous: activate(g.members[(i - 1 + n) % n])
        case .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8:
            let k = Int(action.rawValue - HotKeys.Action.tab1.rawValue)
            if k < n { activate(g.members[k]) }
        case .last: activate(g.members[n - 1])
        case .close: close(g.activeID)
        case .moveToNewWindow: moveToNewWindow(g.activeID)
        case .rename: beginRename(g.activeID)
        }
    }

    func stripDoubleClicked(_ gid: UUID) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": minimize(gid)
        case "None": break
        default: toggleFill(gid) // "Fill" / "Maximize" (zoom): the group's Fill
        }
    }

    private func tearOffFrame(cursor: CGPoint, size: CGSize) -> CGRect {
        // The cursor holds the window by its title bar, like Safari's torn-off tab.
        CGRect(x: cursor.x - size.width / 2, y: cursor.y - 14, width: size.width, height: size.height)
    }

    // MARK: Moving the group

    /// The active member's title bar is being dragged (from `DragCoordinator`): the strip follows
    /// the window server's bounds live; the others catch up on mouse up (§5.6, P3).
    func memberDragMoved(_ id: CGWindowID, bounds: CGRect) {
        guard let gid = groupOf[id], var g = groups[gid], g.activeID == id else { return }
        if liveDrag?.group != gid {
            liveDrag = (gid, g.content)
            tuckBackground(gid)
        }
        g.content = bounds
        groups[gid] = g
        strips[gid]?.follow(content: bounds)
    }

    func memberDragEnded(_ id: CGWindowID) {
        guard let drag = liveDrag else { return }
        liveDrag = nil
        if let bounds = windowBounds( id), var g = groups[drag.group] {
            g.content = bounds
            groups[drag.group] = g
            strips[drag.group]?.place(content: bounds, above: id)
        }
        // The active window is already where the user left it. Writing its frame again could
        // land after macOS tiles it (an edge drop) and undo the tile.
        syncMembers(of: drag.group, reconcile: false, skipping: id)
    }

    /// Dragging the strip's empty area moves the whole group (§5.7): the strip moves with the
    /// cursor, the active window follows with one position write at a time, the rest on mouse up.
    func stripDragChanged(_ gid: UUID, cursor: CGPoint) {
        guard let g = groups[gid] else { return }
        if stripDrag?.group != gid {
            stripDrag = (gid, g.content, cursor, false, nil)
            tuckBackground(gid)
        }
        guard var d = stripDrag else { return }
        let origin = CGPoint(x: d.startContent.minX + cursor.x - d.startMouse.x, y: d.startContent.minY + cursor.y - d.startMouse.y)
        var moved = g
        moved.content.origin = origin
        groups[gid] = moved
        strips[gid]?.follow(content: moved.content)
        if d.inFlight { d.pending = origin; stripDrag = d; return }
        d.inFlight = true
        stripDrag = d
        sendStripDragPosition(gid, origin)
    }

    private func sendStripDragPosition(_ gid: UUID, _ origin: CGPoint) {
        guard let g = groups[gid] else { return }
        setPosition(g.activeID, origin) { [weak self] in
            guard let self, var d = self.stripDrag, d.group == gid else { return }
            if let next = d.pending {
                d.pending = nil
                self.stripDrag = d
                self.sendStripDragPosition(gid, next)
            } else {
                d.inFlight = false
                self.stripDrag = d
            }
        }
    }

    func stripDragEnded(_ gid: UUID) {
        guard stripDrag?.group == gid else { return }
        stripDrag = nil
        syncMembers(of: gid, reconcile: false, activeFirst: true)
    }

    // MARK: Dissolve and quit

    private func dissolve(_ gid: UUID) {
        guard let g = groups.removeValue(forKey: gid) else { return }
        for id in g.members {
            groupOf[id] = nil
            lastFit[id] = nil
            misfitParked.remove(id)
        }
        resyncTimers.removeValue(forKey: gid)?.invalidate()
        if let strip = strips.removeValue(forKey: gid) { strip.dismiss() }
        updateFocus()
        guard let last = g.members.first else { return }
        FileLog.shared.write("dissolve group=\(gid.uuidString.prefix(8))")
        // The last window grows back into the strip's space (§5.8).
        let outer = g.outer
        if g.isMinimized { return command(.setMinimized(false), last) }
        guard animates, !Motion.reduced, let entry = registry.windows[last] else { return setFrame(last, outer) }
        Task { @MainActor in
            let image = await WindowCapture.capture(last)
            let proxy = image.map { WindowProxy(image: $0, appPID: entry.app.pid, appName: entry.app.name, on: outer) }
            proxy?.show(at: g.content)
            self.setFrame(last, outer)
            await proxy?.spring(to: outer)
            if let proxy, let final = await WindowCapture.capture(last) { proxy.crossfade(to: final) }
            await proxy?.fadeOut()
        }
    }

    /// Quit (PLAN.md §5.12): untab everything and close nothing. Strips go, every window gets
    /// its strip space back, parked windows come back, and the tabs fan out so none stay hidden.
    /// Calls `done` when every window has answered, or after `timeout` (a hung app can't block quitting).
    /// `done(true)` once every window answered; `done(false)` when the time cap ran out first,
    /// so the recovery file should stay for the next launch.
    func restoreAll(timeout: TimeInterval = 2, done: @escaping (_ allLanded: Bool) -> Void) {
        let all = groups.values
        groups.removeAll()
        groupOf.removeAll()
        cancelRecoverySave()
        resyncTimers.values.forEach { $0.invalidate() }
        resyncTimers.removeAll()
        strips.values.forEach { $0.dismiss() }
        strips.removeAll()
        updateFocus()
        // Every move is counted before any is sent: an app that answers at once must not
        // bring the count to zero while other windows are still to come.
        var moves: [(id: CGWindowID, pid: pid_t, frame: CGRect)] = []
        var raises: [(id: CGWindowID, pid: pid_t)] = []
        for g in all {
            let order = [g.activeID] + g.inactive
            let visible = visibleFrame(containing: g.outer)
            // A minimized group's window stays in the Dock where the user put it (§5.12 step 4);
            // its parked group-mates come back on screen.
            let onScreen = g.isMinimized ? g.inactive : order
            let plan = GroupGeometry.cascade(outer: g.outer, activeFirst: onScreen, visibleFrame: visible)
            for id in onScreen {
                guard let entry = registry.windows[id], let frame = plan[id] else { continue }
                moves.append((id, entry.app.pid, frame))
            }
            if !g.isMinimized, let entry = registry.windows[g.activeID] { raises.append((g.activeID, entry.app.pid)) }
        }
        let tracker = RestoreTracker(done: done)
        tracker.pending = moves.count
        for m in moves {
            system.perform(.setFrame(m.frame), window: m.id, pid: m.pid) { _ in tracker.completeOne() }
        }
        for r in raises { system.perform(.raise, window: r.id, pid: r.pid, completion: nil) }
        FileLog.shared.write("restore all groups=\(all.count) windows=\(moves.count)")
        if moves.isEmpty { return tracker.finish(allLanded: true) }
        // A run-loop timer in common modes, so it fires inside Quit's nested run loop too.
        let cap = Timer(timeInterval: timeout, repeats: false) { _ in MainActor.assumeIsolated { tracker.finish(allLanded: false) } }
        RunLoop.main.add(cap, forMode: .common)
    }

    /// Permission revoked: AX is gone, so just drop everything Tabsome drew (§5.8).
    /// Accessibility was turned off: Tabsome can't move windows, so it lets go of the groups
    /// where they are. The recovery file stays, so they're undone once it's back (§5.8).
    func abandonAll() {
        strips.values.forEach { $0.dismiss() }
        strips.removeAll()
        groups.removeAll()
        groupOf.removeAll()
        cancelRecoverySave()
        pendingRecovery = nil
        updateFocus()
    }

    // MARK: Crash recovery (§5.12, P7)

    /// Every group's windows and outer frame: what the next launch needs if this one never gets
    /// to run its quit restore.
    func recoveryState() -> RecoveryState {
        func window(_ id: CGWindowID) -> RecoveryState.Window? {
            registry.windows[id].map { .init(id: id, pid: $0.app.pid, bundleID: $0.app.bundleID) }
        }
        let saved = groups.values.sorted { $0.id.uuidString < $1.id.uuidString }.compactMap { g -> RecoveryState.Group? in
            guard let active = window(g.activeID) else { return nil }
            return .init(outer: g.outer, active: active, others: g.inactive.compactMap(window), minimized: g.isMinimized)
        }
        return RecoveryState(groups: saved)
    }

    private func scheduleRecoverySave() {
        guard onRecoveryStateChanged != nil else { return }
        recoverySave?.invalidate()
        // Coalesced: a drag changes the group frame many times a second.
        recoverySave = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recoverySave = nil
                self.onRecoveryStateChanged?(self.recoveryState())
            }
        }
    }

    private func cancelRecoverySave() {
        recoverySave?.invalidate()
        recoverySave = nil
    }

    /// The last run stopped without undoing its groups (a crash, Force Quit, or Accessibility
    /// turned off): undo them now, the same way Quit does. Waits up to `timeout` for the
    /// recorded windows to appear in the registry, then restores whichever are still there.
    /// A window counts only if its ID still belongs to the same process.
    func recover(_ state: RecoveryState, timeout: TimeInterval = 3, done: @escaping () -> Void) {
        pendingRecovery = (state, done)
        recoverIfReady()
        guard pendingRecovery != nil else { return }
        let cap = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.finishRecovery() } }
        RunLoop.main.add(cap, forMode: .common)
    }

    private func recoverIfReady() {
        guard let pending = pendingRecovery else { return }
        let windows = pending.state.groups.flatMap { [$0.active] + $0.others }
        if windows.allSatisfy({ registry.windows[$0.id]?.app.pid == $0.pid }) { finishRecovery() }
    }

    private func finishRecovery() {
        guard let pending = pendingRecovery else { return }
        pendingRecovery = nil
        var moved = 0
        for g in pending.state.groups {
            // Skip windows that are gone, or that the user has already tabbed again.
            let here = { (w: RecoveryState.Window) in self.registry.windows[w.id]?.app.pid == w.pid && self.groupOf[w.id] == nil }
            let windows = ([g.active] + g.others).filter(here).map(\.id)
            let onScreen = g.minimized ? g.others.filter(here).map(\.id) : windows
            let plan = GroupGeometry.cascade(outer: g.outer, activeFirst: onScreen, visibleFrame: visibleFrame(containing: g.outer))
            for id in onScreen {
                guard let frame = plan[id] else { continue }
                setFrame(id, frame)
                moved += 1
            }
            if !g.minimized, here(g.active) { command(.raise, g.active.id) }
        }
        FileLog.shared.write("recovered groups=\(pending.state.groups.count) windows=\(moved)")
        pending.done()
    }

    // MARK: Registry events (§5.8)

    private func windowUpdated(old: WindowRegistry.Entry?, new: WindowRegistry.Entry) {
        let id = new.id
        guard let gid = groupOf[id], var g = groups[gid] else { return }
        let w = new.window
        if w.isFullScreen {
            // Full screen moves the window to its own Space: it leaves the group.
            return removeMember(id, closing: false)
        }
        if w.isMinimized != (old?.window.isMinimized ?? false) {
            if w.isMinimized, !g.isMinimized { return minimizeFromMember(gid, id) }
            if !w.isMinimized, g.isMinimized, id == g.activeID { return restoreFromMinimize(gid) }
        }
        if old?.window.title != w.title || old?.app.name != new.app.name { refreshStrip(gid) }
        guard old?.window.frame != w.frame, !g.isMinimized, liveDrag?.group != gid, stripDrag?.group != gid else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if expected.isExpected(w.frame, for: id, now: now) { return }
        // Moved somewhere else right after Tabsome placed it, with no mouse involved: something
        // is moving it back. Once that adds up to a fight, Tabsome lets go of the window (P4).
        if NSEvent.pressedMouseButtons & 1 == 0, expected.wroteRecently(id, now: now), fights.record(id, now: now) {
            return letGoAfterFight(id, app: new.app)
        }
        // While the mouse is down, a move or resize is the user's, settling or not.
        if let until = settlingUntil[gid], now < until, NSEvent.pressedMouseButtons & 1 == 0 {
            // Tabsome is still moving this group's windows: an in-between frame (or a window that
            // lagged behind) isn't the user moving the group. Check again once things settle.
            return scheduleSettleCheck(gid)
        }
        if id == g.activeID {
            // The user moved or resized the active window: the group follows it. While the
            // mouse is down (resizing from an edge), the background tabs are tucked away.
            g.content = w.frame
            groups[gid] = g
            strips[gid]?.place(content: w.frame, above: id)
            if NSEvent.pressedMouseButtons & 1 == 1 { tuckBackground(gid) }
        }
        scheduleResync(gid)
    }

    /// The member's own yellow button (or ⌘M) minimizes the whole group (§5.8).
    private func minimizeFromMember(_ gid: UUID, _ id: CGWindowID) {
        guard var g = groups[gid] else { return }
        if g.activeID != id { g.activate(id) }
        g.isMinimized = true
        groups[gid] = g
        strips[gid]?.hide()
        for other in g.inactive { park(other, from: g) }
    }

    private func letGoAfterFight(_ id: CGWindowID, app: WindowRegistry.AppInfo) {
        FileLog.shared.write("fight: window=\(id) of \(app.bundleID ?? "?") keeps being moved back; taking it out of its group")
        fights.forget(id)
        removeMember(id, closing: false)
        onFight?(app.name, app.bundleID)
    }

    /// Settings › Apps changed: windows of newly excluded apps leave their groups, each as its
    /// own window, cascaded so it's visible (like Move Tab to New Window).
    func removeExcluded(_ excluded: Set<String>) {
        let leaving = groupOf.keys.filter { id in registry.windows[id]?.app.bundleID.map(excluded.contains) ?? false }
        for id in leaving.sorted() where groupOf[id] != nil { moveToNewWindow(id) }
    }

    private func windowRemoved(_ id: CGWindowID) {
        expected.forget(id)
        fights.forget(id)
        guard groupOf[id] != nil else { return }
        removeMember(id, closing: true)
    }

    /// Removes a tab; activates the right neighbor if it was active; dissolves a group of one.
    private func removeMember(_ id: CGWindowID, closing: Bool) {
        guard let gid = groupOf.removeValue(forKey: id), var g = groups[gid] else { return }
        let newActive = g.remove(id)
        groups[gid] = g
        lastFit[id] = nil
        misfitParked.remove(id)
        if g.shouldDissolve { return dissolve(gid) }
        refreshStrip(gid)
        if let newActive { bringBack(newActive, in: g) { self.activateWindow(newActive) { self.conceal(gid) } } }
    }

    private func isOwnActivation(_ pid: pid_t) -> Bool {
        guard let until = ownActivation[pid] else { return false }
        if ProcessInfo.processInfo.systemUptime < until { return true }
        ownActivation[pid] = nil
        return false
    }

    private func mainWindowChanged(pid: pid_t, id: CGWindowID?) {
        guard !isOwnActivation(pid), let id, let gid = groupOf[id], let g = groups[gid], g.activeID != id, !g.isMinimized,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        // The user brought an inactive tab's window forward (⌘Tab, a click, Mission Control):
        // that's a tab switch.
        switchActive(gid, to: id)
    }

    private func appActivated(_ pid: pid_t) {
        defer {
            updateFocus()
            scheduleStripCheck()
        }
        let own = isOwnActivation(pid)
        for (gid, g) in groups where !g.isMinimized {
            if !own, let main = registry.mainWindow[pid], g.inactive.contains(main) {
                switchActive(gid, to: main)
            } else {
                strips[gid]?.reorder(above: g.activeID)
                refreshStrip(gid)
            }
        }
    }

    private func switchActive(_ gid: UUID, to id: CGWindowID) {
        guard var g = groups[gid] else { return }
        g.activate(id)
        groups[gid] = g
        refreshStrip(gid)
        strips[gid]?.reorder(above: id)
        bringBack(id, in: g) { self.conceal(gid) }
    }

    // MARK: Spaces, hidden apps, displays, wake (§5.8)

    /// Once the window server has caught up with the change (a Space switch animates).
    private func scheduleStripCheck() {
        stripCheck?.invalidate()
        stripCheck = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.revalidateStrips() }
        }
    }

    /// A strip shows only where its active window is: it hides when the window is on another
    /// Space or its app is hidden, and joins the window's Space when the user goes there.
    func revalidateStrips() {
        let onScreen = onScreenWindows()
        for (gid, g) in groups where !g.isMinimized {
            strips[gid]?.setWindowOnScreen(onScreen.contains(g.activeID))
        }
    }

    /// A display was added, removed, or rearranged. A group that's no longer mostly on a screen
    /// moves onto one (shrinking if it must); every group re-syncs, and background tabs parked
    /// in a corner are parked again on their group's current screen.
    func revalidateScreens() {
        let areas = usableAreas()
        for (gid, var g) in groups where !g.isMinimized {
            if let outer = GroupGeometry.refitToScreens(outer: g.outer, visibleFrames: areas) {
                FileLog.shared.write("display change: moving group=\(gid.uuidString.prefix(8)) onto a screen")
                g.content = StripLayout.frames(outer: outer, placement: g.placement).content
                groups[gid] = g
            }
            for id in g.inactive { misfitParked.remove(id) }
            markSettling(gid)
            strips[gid]?.place(content: g.content, above: g.activeID)
            syncMembers(of: gid, reconcile: true) { self.scheduleSettleCheck(gid) }
        }
        scheduleStripCheck()
    }

    /// After wake (once the registry has re-read every app): the same checks as a display change.
    func revalidateAll() {
        revalidateScreens()
    }

    // MARK: Concealment (§5.5)

    private func predictedSize(_ id: CGWindowID, _ g: TabGroup) -> CGSize {
        GroupGeometry.predictedSize(for: g.content.size, last: lastFit[id])
    }

    /// A background tab that would show around the active one at the group frame: a minimum
    /// size bigger than the group, a fixed size, or an active tab that came out smaller.
    private func sticksOut(_ id: CGWindowID, _ g: TabGroup) -> Bool {
        !GroupGeometry.isCovered(predictedSize(id, g), by: predictedSize(g.activeID, g))
    }

    /// A member that can't take the group frame exactly, so checking it against the frame
    /// would only fight it.
    private func isMisfit(_ id: CGWindowID, _ g: TabGroup) -> Bool {
        let size = predictedSize(id, g)
        return !ExpectedFrames.close(CGRect(origin: .zero, size: size), CGRect(origin: .zero, size: g.content.size))
    }

    private func recordFit(_ id: CGWindowID, requested: CGSize, landed: CGRect?) {
        if let landed { lastFit[id] = (requested, landed.size) }
    }

    /// Background tabs stay stacked behind the active window when it covers them; ones that
    /// would show around it wait in a screen corner (AeroSpace's way) until they're activated.
    private func conceal(_ gid: UUID) {
        guard let g = groups[gid], !g.isMinimized, !tucked.contains(gid) else { return }
        misfitParked.remove(g.activeID)
        for id in g.inactive {
            if sticksOut(id, g) {
                guard !misfitParked.contains(id) else { continue }
                FileLog.shared.write("conceal: window=\(id) can't hide behind the active tab; parking it")
                misfitParked.insert(id)
                park(id, from: g)
            } else if misfitParked.remove(id) != nil {
                let size = g.content.size
                setFrame(id, g.content) { self.recordFit(id, requested: size, landed: $0) }
            }
        }
    }

    /// A tab coming forward from its corner goes back to the group frame first.
    private func bringBack(_ id: CGWindowID, in g: TabGroup, then: @escaping () -> Void) {
        guard misfitParked.remove(id) != nil else { return then() }
        let size = g.content.size
        setFrame(id, g.content) { landed in
            self.recordFit(id, requested: size, landed: landed)
            then()
        }
    }

    // MARK: Frame sync (FrameSync, P3, P5)

    /// After a move or resize of the active window settles and the mouse is up, bring the other
    /// members to the group frame. Nothing is written to other apps mid-drag (P3).
    private func scheduleResync(_ gid: UUID) {
        resyncTimers[gid]?.invalidate()
        resyncTimers[gid] = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 1 { return self.scheduleResync(gid) }
                self.resyncTimers[gid] = nil
                if !self.refitIfTiled(gid) { self.syncMembers(of: gid, reconcile: true) }
            }
        }
    }

    /// Writes the group frame to every member that isn't there yet. With `reconcile`, the group
    /// then adopts the strictest frame the members actually took (Terminal's grid) and re-applies it.
    /// macOS tiled the active window (§5.8): it fills a tile with no room for the strip. The
    /// group's outer frame takes the tile instead, and the window shrinks by the strip's
    /// thickness, so the result matches a tiled ordinary window. Checked once the window has
    /// stopped moving, after macOS's tiling animation.
    @discardableResult
    func refitIfTiled(_ gid: UUID) -> Bool {
        guard var g = groups[gid], !g.isMinimized else { return false }
        let tile = g.content
        guard GroupGeometry.isTile(tile, visibleFrame: visibleFrame(containing: tile)) else { return false }
        g.content = StripLayout.frames(outer: tile, placement: g.placement).content
        groups[gid] = g
        FileLog.shared.write("refit group=\(gid.uuidString.prefix(8)) tile=\(tile)")
        markSettling(gid)
        strips[gid]?.place(content: g.content, above: g.activeID)
        syncMembers(of: gid, reconcile: true, activeFirst: true) { self.scheduleSettleCheck(gid) }
        return true
    }

    private func markSettling(_ gid: UUID) {
        settlingUntil[gid] = ProcessInfo.processInfo.systemUptime + settleDuration
    }

    private func scheduleSettleCheck(_ gid: UUID, after delay: TimeInterval = 0.35) {
        settleTimers[gid]?.invalidate()
        settleTimers[gid] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settleTimers[gid] = nil
                self?.settleCheck(gid)
            }
        }
    }

    /// After Tabsome moves a group's windows, every member must actually be at the group frame.
    /// A window whose report arrived mid-move, or whose app answered late, is put back (found in
    /// Phase 4: one window of a multi-tab merge could be left outside the group).
    func settleCheck(_ gid: UUID) {
        guard let g = groups[gid], !g.isMinimized, !tucked.contains(gid), liveDrag?.group != gid, stripDrag?.group != gid else { return }
        for id in g.members where !misfitParked.contains(id) && !isMisfit(id, g) {
            guard let actual = windowBounds(id) ?? registry.windows[id]?.window.frame else { continue }
            if !ExpectedFrames.close(actual, g.content) {
                FileLog.shared.write("settle: window=\(id) was off the group frame; putting it back")
                setFrame(id, g.content)
            }
        }
    }

    /// Moving or resizing the active window would expose the background tabs it was covering,
    /// so they go to a screen corner (one write each) and come back on mouse up, when the group
    /// is re-synced: two writes per tab per interaction instead of a stream (P3).
    private func tuckBackground(_ gid: UUID) {
        guard !tucked.contains(gid), let g = groups[gid], !g.isMinimized else { return }
        tucked.insert(gid)
        for id in g.inactive { park(id, from: g) }
    }

    private func park(_ id: CGWindowID, from g: TabGroup) {
        let screen = screenFrame(containing: g.outer)
        let others = NSScreen.screens.map { ScreenGeometry.cgRect(fromAppKit: $0.frame) }.filter { $0 != screen }
        let size = registry.windows[id]?.window.frame.size ?? g.content.size
        setPosition(id, GroupGeometry.parkingOrigin(screen: screen, size: size, otherScreens: others))
    }

    private func syncMembers(of gid: UUID, reconcile: Bool, activeFirst: Bool = false, skipping skipped: CGWindowID? = nil, then: (() -> Void)? = nil) {
        tucked.remove(gid)
        guard let g = groups[gid] else { then?(); return }
        let requested = g.content
        // Background tabs known to show around the active one stay in their corner (§5.5).
        let members = g.members.filter { id in
            guard id != skipped, let f = registry.windows[id]?.window.frame else { return false }
            if id != g.activeID, sticksOut(id, g) { return false }
            return f != requested || !reconcile
        }
        let finish = {
            self.conceal(gid)
            then?()
        }
        guard !members.isEmpty else { return finish() }
        var landed: [CGRect] = []
        var remaining = members.count
        for id in members {
            setFrame(id, requested) { frame in
                if let frame { landed.append(frame) }
                self.recordFit(id, requested: requested.size, landed: frame)
                remaining -= 1
                guard remaining == 0 else { return }
                guard reconcile, var g = self.groups[gid], g.content == requested else { return finish() }
                var strict = GroupGeometry.reconcile(requested: requested, landed: landed)
                guard strict != requested else { return finish() }
                if strict.width > requested.width || strict.height > requested.height {
                    // Grown to fit a member's minimum size: still on screen, strip included.
                    let outer = StripLayout.outer(content: strict, placement: g.placement)
                    let fitted = GroupGeometry.keepOnScreen(outer, visibleFrame: self.visibleFrame(containing: outer))
                    strict = StripLayout.frames(outer: fitted, placement: g.placement).content
                    FileLog.shared.write("group=\(gid.uuidString.prefix(8)) grew to \(Int(strict.width))x\(Int(strict.height)) to fit a member's minimum size")
                }
                g.content = strict
                self.groups[gid] = g
                self.strips[gid]?.place(content: strict, above: g.activeID)
                self.syncMembers(of: gid, reconcile: false, then: then)
            }
        }
    }

    // MARK: Commands

    private func setFrame(_ id: CGWindowID, _ frame: CGRect, done: ((CGRect?) -> Void)? = nil) {
        guard let entry = registry.windows[id] else { done?(nil); return }
        expected.expect(frame, for: id, now: ProcessInfo.processInfo.systemUptime)
        system.perform(.setFrame(frame), window: id, pid: entry.app.pid) { [weak self] result in
            if let landed = result.frame { self?.expected.expect(landed, for: id, now: ProcessInfo.processInfo.systemUptime) }
            done?(result.frame)
        }
    }

    private func setPosition(_ id: CGWindowID, _ origin: CGPoint, done: (() -> Void)? = nil) {
        guard let entry = registry.windows[id] else { done?(); return }
        let size = entry.window.frame.size
        expected.expect(CGRect(origin: origin, size: size), for: id, now: ProcessInfo.processInfo.systemUptime)
        system.perform(.setPosition(origin), window: id, pid: entry.app.pid) { [weak self] result in
            if let landed = result.frame { self?.expected.expect(landed, for: id, now: ProcessInfo.processInfo.systemUptime) }
            done?()
        }
    }

    private func command(_ c: WindowCommand, _ id: CGWindowID) {
        guard let entry = registry.windows[id] else { return }
        system.perform(c, window: id, pid: entry.app.pid, completion: nil)
    }

    /// Stacking concealment's switch (§5.5): raise the window, then activate its app.
    private func activateWindow(_ id: CGWindowID, then: (() -> Void)? = nil) {
        guard let entry = registry.windows[id] else { then?(); return }
        let pid = entry.app.pid
        ownActivation[pid] = ProcessInfo.processInfo.systemUptime + 0.6
        system.perform(.raise, window: id, pid: pid) { [weak self] _ in
            NSRunningApplication(processIdentifier: pid)?.activate()
            if let gid = self?.groupOf[id] { self?.strips[gid]?.reorder(above: id) }
            then?()
        }
    }

    // MARK: Strips

    private func strip(for g: TabGroup) -> TabBarWindow {
        if let existing = strips[g.id] {
            refreshStrip(g.id)
            return existing
        }
        let gid = g.id
        let strip = TabBarWindow(actions: .init(
            activate: { [weak self] id in self?.activate(id) },
            close: { [weak self] id in self?.close(id) },
            closeAll: { [weak self] in self?.closeAll(gid) },
            minimize: { [weak self] in self?.minimize(gid) },
            fill: { [weak self] in self?.toggleFill(gid) },
            tearOffBegan: { [weak self] ids, grabbed, p in self?.tearOffBegan(ids, grabbed: grabbed, cursor: p) },
            tearOffMoved: { [weak self] p in self?.tearOffMoved(cursor: p) },
            tearOffEnded: { [weak self] p in self?.tearOffEnded(cursor: p) },
            tearOffCancelled: { [weak self] in self?.tearOffCancelled() },
            stripDragChanged: { [weak self] p in self?.stripDragChanged(gid, cursor: p) },
            stripDragEnded: { [weak self] in self?.stripDragEnded(gid) },
            reorder: { [weak self] id, index in self?.reorder(id, to: index) },
            closeOthers: { [weak self] id in self?.closeOthers(id) },
            closeToTheRight: { [weak self] id in self?.closeToTheRight(id) },
            moveToNewWindow: { [weak self] ids, active in self?.moveToNewWindow(ids, active: active) },
            closeTabs: { [weak self] ids in self?.closeTabs(ids) },
            addCandidates: { [weak self] in self?.addCandidates(for: gid) ?? [] },
            add: { [weak self] id in self?.add(id, to: gid) },
            doubleClicked: { [weak self] in self?.stripDoubleClicked(gid) },
            rename: { [weak self] id, name, refocus in self?.rename(id, to: name, refocus: refocus) },
            cancelRename: { [weak self] id in self?.refocus(id) }))
        strip.placement = g.placement
        strips[g.id] = strip
        refreshStrip(g.id)
        return strip
    }

    private func refreshStrip(_ gid: UUID) {
        guard let g = groups[gid], let strip = strips[gid] else { return }
        let entries = g.members.compactMap { registry.windows[$0] }
        let tabs = entries.map { e in
            TabItem(id: e.id, label: TabLabel.label(for: e, among: entries, customName: registry.customNames[e.id]), pid: e.app.pid,
                    title: e.window.title, isActive: e.id == g.activeID, isRenamed: registry.customNames[e.id] != nil)
        }
        let focused = registry.windows[g.activeID].map { NSWorkspace.shared.frontmostApplication?.processIdentifier == $0.app.pid } ?? false
        strip.update(tabs: tabs, focused: focused)
        updateFocus()
    }

    // MARK: Screens

    private func screenFrame(containing rect: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { ScreenGeometry.cgRect(fromAppKit: $0.frame).contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.screens.first
        return screen.map { ScreenGeometry.cgRect(fromAppKit: $0.frame) } ?? rect
    }

    private func visibleFrame(containing rect: CGRect) -> CGRect { usableArea(rect) }
}

/// Counts the quit restore's window moves and calls `done` once: when they've all answered, or
/// at the time cap, whichever comes first.
@MainActor
private final class RestoreTracker {
    var pending = 0
    private var done: ((Bool) -> Void)?

    init(done: @escaping (Bool) -> Void) { self.done = done }

    func completeOne() {
        pending -= 1
        if pending == 0 { finish(allLanded: true) }
    }

    func finish(allLanded: Bool) {
        let d = done
        done = nil
        d?(allLanded)
    }
}
