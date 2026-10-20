import AppKit
import CoreGraphics

/// Owns every group (PLAN.md §4): merge, switch, close, dissolve, minimize, fill, tear-out,
/// move/resize sync, and the quit restore. It talks to other apps only through `WindowSystem`
/// commands, which run on each app's AX thread.
@MainActor
@Observable
final class GroupManager {
    private(set) var groups: [UUID: TabGroup] = [:]

    @ObservationIgnored private var groupOf: [CGWindowID: UUID] = [:]
    @ObservationIgnored private var strips: [UUID: TabBarWindow] = [:]
    @ObservationIgnored private var expected = ExpectedFrames()
    @ObservationIgnored private var resyncTimers: [UUID: Timer] = [:]
    @ObservationIgnored private var liveDrag: (group: UUID, startContent: CGRect)?
    @ObservationIgnored private var stripDrag: (group: UUID, startContent: CGRect, startMouse: CGPoint, inFlight: Bool, pending: CGPoint?)?
    @ObservationIgnored private var tearOff: (window: CGWindowID, group: UUID, proxy: WindowProxy?, size: CGSize)?
    @ObservationIgnored private var workspaceObserver: NSObjectProtocol?
    /// Apps Tabsome itself just activated: their focus events aren't the user switching tabs.
    @ObservationIgnored private var ownActivation: [pid_t: TimeInterval] = [:]
    @ObservationIgnored private let system: WindowSystem
    @ObservationIgnored private let registry: WindowRegistry
    /// Off in tests; proxies need a window server.
    @ObservationIgnored var animates = true
    /// Asked before the red button closes every tab (PLAN.md §5.11); returns false to cancel.
    @ObservationIgnored var confirmCloseAll: ((_ count: Int) -> Bool)?

    init(registry: WindowRegistry, system: WindowSystem) {
        self.registry = registry
        self.system = system
        registry.onWindowUpdated = { [weak self] old, new in self?.windowUpdated(old: old, new: new) }
        registry.onWindowRemoved = { [weak self] id, _ in self?.windowRemoved(id) }
        registry.onMainWindowChanged = { [weak self] pid, id in self?.mainWindowChanged(pid: pid, id: id) }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.appActivated(pid) } }
        }
    }

    func group(containing id: CGWindowID) -> TabGroup? { groupOf[id].flatMap { groups[$0] } }
    func isActiveMember(_ id: CGWindowID) -> Bool { group(containing: id)?.activeID == id }

    // MARK: Merge (PLAN.md §5.4)

    /// Tabs `dragged` into `target`'s window (or `target`'s group). `dropFrame` is where the
    /// dragged window was let go; `snapshot` was captured during the dwell (§5.9).
    func merge(dragged d: CGWindowID, into t: CGWindowID, dropFrame: CGRect?, snapshot: CGImage?) {
        guard groupOf[d] == nil, d != t, let dEntry = registry.windows[d], let tEntry = registry.windows[t] else { return }
        let cover: CGWindowID
        var group: TabGroup
        if let gid = groupOf[t], var existing = groups[gid] {
            cover = existing.activeID
            existing.add(d)
            existing.activate(d)
            group = existing
        } else {
            cover = t
            let outer = ScreenWindows.bounds(of: t) ?? tEntry.window.frame
            group = TabGroup(members: [t, d], active: d, content: StripLayout.frames(outer: outer, placement: .top).content)
            groupOf[t] = group.id
        }
        groupOf[d] = group.id
        groups[group.id] = group
        FileLog.shared.write("merge window=\(d) into=\(t) group=\(group.id.uuidString.prefix(8)) tabs=\(group.count)")

        let from = dropFrame ?? dEntry.window.frame
        let gid = group.id
        let proxy = animates && !Motion.reduced ? WindowProxy(image: snapshot, appPID: dEntry.app.pid, appName: dEntry.app.name, on: from) : nil
        proxy?.show(at: from)

        // Cover: the window being tabbed into comes to the front, so the dropped window can move
        // into place behind it, unseen, while its proxy springs there (§5.9).
        activateWindow(cover) {
            self.syncMembers(of: gid, reconcile: true) {
                guard let g = self.groups[gid] else { return }
                let strip = self.strip(for: g)
                strip.place(content: g.content, above: cover)
                strip.show()
                FileLog.shared.write("strip shown group=\(gid.uuidString.prefix(8))")
                guard let proxy else { return self.activateWindow(d) }
                Task { @MainActor in
                    await proxy.spring(to: g.content)
                    self.activateWindow(d)
                    if let final = await WindowCapture.capture(d) { proxy.crossfade(to: final) }
                    await proxy.fadeOut()
                }
            }
        }
    }

    // MARK: Tabs

    /// Click a tab: raise that window, activate its app, and put the strip above it (§5.7).
    func activate(_ id: CGWindowID) {
        guard let gid = groupOf[id], var g = groups[gid] else { return }
        g.activate(id)
        groups[gid] = g
        refreshStrip(gid)
        activateWindow(id)
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
        let corner = GroupGeometry.parkingOrigin(screen: screenFrame(containing: g.outer))
        for id in g.inactive { setPosition(id, corner) }
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
        strips[gid]?.place(content: g.content, above: g.activeID)
        syncMembers(of: gid, reconcile: true, activeFirst: true)
    }

    // MARK: Tear-out (§5.7)

    func tearOffBegan(_ id: CGWindowID, cursor: CGPoint) {
        guard let gid = groupOf[id], let g = groups[gid], let entry = registry.windows[id] else { return }
        let frame = tearOffFrame(cursor: cursor, size: g.content.size)
        let proxy = animates ? WindowProxy(image: nil, appPID: entry.app.pid, appName: entry.app.name, on: frame) : nil
        proxy?.show(at: frame, lifted: true)
        tearOff = (id, gid, proxy, g.content.size)
        Task { @MainActor in
            if let image = await WindowCapture.capture(id), self.tearOff?.window == id { proxy?.setImage(image) }
        }
    }

    func tearOffMoved(cursor: CGPoint) {
        guard let t = tearOff else { return }
        t.proxy?.move(to: tearOffFrame(cursor: cursor, size: t.size))
    }

    /// Let go: the window leaves the group where the ghost is, as a normal window at the group's
    /// size. A group left with one window dissolves.
    func tearOffEnded(cursor: CGPoint) {
        guard let t = tearOff else { return }
        tearOff = nil
        let frame = tearOffFrame(cursor: cursor, size: t.size)
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
        Task { @MainActor in await t.proxy?.fadeOut() }
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
        if liveDrag?.group != gid { liveDrag = (gid, g.content) }
        g.content = bounds
        groups[gid] = g
        strips[gid]?.follow(content: bounds)
    }

    func memberDragEnded(_ id: CGWindowID) {
        guard let drag = liveDrag else { return }
        liveDrag = nil
        if let bounds = ScreenWindows.bounds(of: id), var g = groups[drag.group] {
            g.content = bounds
            groups[drag.group] = g
            strips[drag.group]?.place(content: bounds, above: id)
        }
        syncMembers(of: drag.group, reconcile: false)
    }

    /// Dragging the strip's empty area moves the whole group (§5.7): the strip moves with the
    /// cursor, the active window follows with one position write at a time, the rest on mouse up.
    func stripDragChanged(_ gid: UUID, cursor: CGPoint) {
        guard let g = groups[gid] else { return }
        if stripDrag?.group != gid { stripDrag = (gid, g.content, cursor, false, nil) }
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
        for id in g.members { groupOf[id] = nil }
        resyncTimers.removeValue(forKey: gid)?.invalidate()
        if let strip = strips.removeValue(forKey: gid) { strip.dismiss() }
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
    func restoreAll(timeout: TimeInterval = 2, done: @escaping () -> Void) {
        let all = groups.values
        groups.removeAll()
        groupOf.removeAll()
        resyncTimers.values.forEach { $0.invalidate() }
        resyncTimers.removeAll()
        strips.values.forEach { $0.dismiss() }
        strips.removeAll()
        let tracker = RestoreTracker(done: done)
        for g in all {
            let order = [g.activeID] + g.inactive
            let visible = visibleFrame(containing: g.outer)
            // A minimized group's window stays in the Dock where the user put it (§5.12 step 4);
            // its parked group-mates come back on screen.
            let plan = GroupGeometry.cascade(outer: g.outer, activeFirst: g.isMinimized ? g.inactive : order, visibleFrame: visible)
            for (id, frame) in plan {
                guard let entry = registry.windows[id] else { continue }
                tracker.pending += 1
                system.perform(.setFrame(frame), window: id, pid: entry.app.pid) { _ in tracker.completeOne() }
            }
            if !g.isMinimized, let entry = registry.windows[g.activeID] {
                system.perform(.raise, window: g.activeID, pid: entry.app.pid, completion: nil)
            }
        }
        FileLog.shared.write("restore all groups=\(all.count) windows=\(tracker.pending)")
        if tracker.pending == 0 { return tracker.finish() }
        // A run-loop timer in common modes, so it fires inside Quit's nested run loop too.
        let cap = Timer(timeInterval: timeout, repeats: false) { _ in MainActor.assumeIsolated { tracker.finish() } }
        RunLoop.main.add(cap, forMode: .common)
    }

    /// Permission revoked: AX is gone, so just drop everything Tabsome drew (§5.8).
    func abandonAll() {
        strips.values.forEach { $0.dismiss() }
        strips.removeAll()
        groups.removeAll()
        groupOf.removeAll()
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
        if id == g.activeID {
            // The user moved or resized the active window: the group follows it.
            g.content = w.frame
            groups[gid] = g
            strips[gid]?.place(content: w.frame, above: id)
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
        let corner = GroupGeometry.parkingOrigin(screen: screenFrame(containing: g.outer))
        for other in g.inactive { setPosition(other, corner) }
    }

    private func windowRemoved(_ id: CGWindowID) {
        expected.forget(id)
        guard groupOf[id] != nil else { return }
        removeMember(id, closing: true)
    }

    /// Removes a tab; activates the right neighbor if it was active; dissolves a group of one.
    private func removeMember(_ id: CGWindowID, closing: Bool) {
        guard let gid = groupOf.removeValue(forKey: id), var g = groups[gid] else { return }
        let newActive = g.remove(id)
        groups[gid] = g
        if g.shouldDissolve { return dissolve(gid) }
        refreshStrip(gid)
        if let newActive { activateWindow(newActive) }
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
                self.syncMembers(of: gid, reconcile: true)
            }
        }
    }

    /// Writes the group frame to every member that isn't there yet. With `reconcile`, the group
    /// then adopts the strictest frame the members actually took (Terminal's grid) and re-applies it.
    private func syncMembers(of gid: UUID, reconcile: Bool, activeFirst: Bool = false, then: (() -> Void)? = nil) {
        guard let g = groups[gid] else { then?(); return }
        let requested = g.content
        let members = g.members.filter { id in
            guard let f = registry.windows[id]?.window.frame else { return false }
            return f != requested || !reconcile
        }
        guard !members.isEmpty else { then?(); return }
        var landed: [CGRect] = []
        var remaining = members.count
        for id in members {
            setFrame(id, requested) { frame in
                if let frame { landed.append(frame) }
                remaining -= 1
                guard remaining == 0 else { return }
                guard reconcile, var g = self.groups[gid], g.content == requested else { then?(); return }
                let strict = GroupGeometry.reconcile(requested: requested, landed: landed)
                guard strict != requested else { then?(); return }
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
            tearOffBegan: { [weak self] id, p in self?.tearOffBegan(id, cursor: p) },
            tearOffMoved: { [weak self] p in self?.tearOffMoved(cursor: p) },
            tearOffEnded: { [weak self] p in self?.tearOffEnded(cursor: p) },
            tearOffCancelled: { [weak self] in self?.tearOffCancelled() },
            stripDragChanged: { [weak self] p in self?.stripDragChanged(gid, cursor: p) },
            stripDragEnded: { [weak self] in self?.stripDragEnded(gid) }))
        strips[g.id] = strip
        refreshStrip(g.id)
        return strip
    }

    private func refreshStrip(_ gid: UUID) {
        guard let g = groups[gid], let strip = strips[gid] else { return }
        let entries = g.members.compactMap { registry.windows[$0] }
        let tabs = entries.map { e in
            TabItem(id: e.id, label: TabLabel.label(for: e, among: entries), pid: e.app.pid, title: e.window.title, isActive: e.id == g.activeID)
        }
        let focused = registry.windows[g.activeID].map { NSWorkspace.shared.frontmostApplication?.processIdentifier == $0.app.pid } ?? false
        strip.update(tabs: tabs, focused: focused)
    }

    // MARK: Screens

    private func screenFrame(containing rect: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { ScreenGeometry.cgRect(fromAppKit: $0.frame).contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.screens.first
        return screen.map { ScreenGeometry.cgRect(fromAppKit: $0.frame) } ?? rect
    }

    private func visibleFrame(containing rect: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { ScreenGeometry.cgRect(fromAppKit: $0.frame).contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.screens.first
        return screen.map { ScreenGeometry.cgRect(fromAppKit: $0.visibleFrame) } ?? rect
    }
}

/// Counts the quit restore's window moves and calls `done` once: when they've all answered, or
/// at the time cap, whichever comes first.
@MainActor
private final class RestoreTracker {
    var pending = 0
    private var done: (() -> Void)?

    init(done: @escaping () -> Void) { self.done = done }

    func completeOne() {
        pending -= 1
        if pending == 0 { finish() }
    }

    func finish() {
        let d = done
        done = nil
        d?()
    }
}
