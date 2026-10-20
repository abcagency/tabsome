import AppKit
import SwiftUI

/// One tab in a strip.
struct TabItem: Identifiable, Equatable {
    let id: CGWindowID
    let label: String
    let pid: pid_t
    /// Shown as the tooltip. Sensitive (S4): UI only, never logged.
    let title: String?
    let isActive: Bool
    var isRenamed = false
}

/// A window the "+" menu offers (PLAN.md §5.6).
struct AddCandidate: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String?

    var menuTitle: String { (title?.isEmpty == false) ? "\(appName) — \(title!)" : appName }
}

/// Everything a strip can ask its group to do. Points are global, top-left origin.
struct StripActions {
    var activate: (CGWindowID) -> Void
    var close: (CGWindowID) -> Void
    var closeAll: () -> Void
    var minimize: () -> Void
    var fill: () -> Void
    /// The selected tabs (in strip order), the one grabbed, and the pointer.
    var tearOffBegan: ([CGWindowID], CGWindowID, CGPoint) -> Void
    var tearOffMoved: (CGPoint) -> Void
    var tearOffEnded: (CGPoint) -> Void
    var tearOffCancelled: () -> Void
    var stripDragChanged: (CGPoint) -> Void
    var stripDragEnded: () -> Void
    var reorder: (CGWindowID, Int) -> Void
    var closeOthers: (CGWindowID) -> Void
    var closeToTheRight: (CGWindowID) -> Void
    /// The tabs (one, or a selection) and the one that stays active.
    var moveToNewWindow: ([CGWindowID], CGWindowID) -> Void
    var closeTabs: ([CGWindowID]) -> Void
    var addCandidates: () -> [AddCandidate]
    var add: (CGWindowID) -> Void
    var doubleClicked: () -> Void
    /// Save a tab's name (nil or empty resets it); `refocus` returns the keyboard to the tab's window.
    var rename: (CGWindowID, String?, Bool) -> Void
    var cancelRename: (CGWindowID) -> Void
}

@MainActor
@Observable
final class TabStripModel {
    var tabs: [TabItem] = []
    var focused = false
    var visible = false
    /// The pointer, in the strip's coordinates (y down), from an always-on tracking area: the
    /// strip's app is never active, so ordinary hover tracking wouldn't fire.
    var hover: CGPoint?
    /// Where a window or tab dragged onto this strip would land (§5.2).
    var insertion: Int?
    /// Chrome's width freeze (§5.6): after a close, tabs keep their width until the pointer leaves.
    var frozenWidth: CGFloat?
    var addCandidates: [AddCandidate] = []
    /// The tab being renamed, and what's typed so far (§5.10).
    var renaming: CGWindowID?
    var renameDraft = ""
    /// Tabs selected with ⇧/⌘-click (always includes the active one).
    var selection = TabSelection(active: 0)

    var order: [CGWindowID] { tabs.map(\.id) }
    var activeID: CGWindowID { tabs.first(where: \.isActive)?.id ?? 0 }
    /// The selection, in strip order, if the tab is part of it; otherwise just the tab.
    func selectedTabs(including id: CGWindowID) -> [CGWindowID] {
        selection.selected.contains(id) ? selection.ordered(order) : [id]
    }
    /// Called when a rename starts or ends, so the panel can take or give up the keyboard.
    @ObservationIgnored var onRenamingChanged: ((Bool) -> Void)?

    func beginRename(_ id: CGWindowID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        renameDraft = tab.label
        withAnimation(Motion.quickFade) { renaming = id }
        onRenamingChanged?(true)
    }

    func endRename() {
        withAnimation(Motion.snappy) { renaming = nil }
        onRenamingChanged?(false)
    }

    /// Saves whatever is typed (§5.10). `refocus` gives the keyboard back to the tab's window;
    /// not when the user clicked somewhere else on purpose.
    @ObservationIgnored var onRename: ((CGWindowID, String?, _ refocus: Bool) -> Void)?
    @ObservationIgnored var onCancelRename: ((CGWindowID) -> Void)?

    func commitRename(refocus: Bool) {
        guard let id = renaming else { return }
        guard let tab = tabs.first(where: { $0.id == id }) else { return endRename() }
        let name = renameDraft
        endRename()
        // Saving the default label unchanged is the same as having no custom name.
        onRename?(id, name == tab.label && !tab.isRenamed ? nil : name, refocus)
    }

    func cancelRename() {
        guard let id = renaming else { return }
        endRename()
        onCancelRename?(id)
    }

    var placement: TabPlacement = .top
    var activeIndex: Int { tabs.firstIndex(where: \.isActive) ?? 0 }
    /// The quiet 50-tab limit (§1): a full strip has no "+".
    var canAdd: Bool { tabs.count < TabGroup.maxTabs }

    /// The layout for a strip of this size, in the current placement.
    func layout(size: CGSize) -> StripLayout.TabsLayout {
        switch placement {
        case .top: layout(width: size.width)
        case .left: StripLayout.left(height: size.height, count: tabs.count, active: activeIndex, showsPlus: canAdd)
        case .leftNamed: StripLayout.left(height: size.height, count: tabs.count, active: activeIndex, showsPlus: canAdd, named: true)
        }
    }

    /// The coordinate along the strip (x in Top mode, y in Left) of a point in strip coordinates.
    func along(_ p: CGPoint) -> CGFloat { placement == .top ? p.x : p.y }

    func layout(width: CGFloat) -> StripLayout.TabsLayout {
        // While renaming, that tab widens to fit what's typed (§5.10), up to what the strip allows.
        let wide = renaming.flatMap { id in tabs.firstIndex { $0.id == id } }.map { ($0, Self.labelWidth(renameDraft) + 64) }
        return StripLayout.top(width: width, count: tabs.count, active: activeIndex, showsPlus: canAdd, frozenWidth: frozenWidth, wide: wide)
    }

    static func labelWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
    }
}

/// The tab strip overlay (PLAN.md §5.6): two non-activating panels per group at normal level,
/// kept directly above the group's active window. The back one draws the glass (the strip and
/// its corner fillets, one continuous shape) and ignores the mouse, so clicks at the fillets
/// reach the app; the front one covers only the strip and holds the tabs (S7; Phase 4 found that
/// transparent parts of a panel still catch clicks).
@MainActor
final class TabBarWindow {
    private let panel = OverlayPanel(clickThrough: false)
    private let backPanel = OverlayPanel(clickThrough: true)
    private let model = TabStripModel()
    private var burst: Timer?
    private var burstUntil: TimeInterval = 0
    private var aboveID: CGWindowID = 0
    private var dismissing = false
    private let actions: StripActions
    /// Left mode's rename field, attached to the right of the icon (§5.10).
    private var renamePanel: OverlayPanel?

    var placement: TabPlacement = .top {
        didSet { model.placement = placement }
    }

    init(actions: StripActions) {
        self.actions = actions
        panel.setHostedContent(StripHostingView(model: model, actions: actions))
        let back = NSHostingView(rootView: StripBackground(model: model))
        back.sizingOptions = []
        backPanel.setHostedContent(back)
        model.onRenamingChanged = { [weak self] editing in self?.renamingChanged(editing) }
        model.onRename = { id, name, refocus in actions.rename(id, name, refocus) }
        model.onCancelRename = { id in actions.cancelRename(id) }
        resignObservers.append(saveRenameOnResignKey(panel))
    }

    private var resignObservers: [NSObjectProtocol] = []

    /// Losing the keyboard (the user clicked another window or tab) saves what's typed (§5.10).
    private func saveRenameOnResignKey(_ window: NSWindow) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.commitRename(refocus: false) }
        }
    }

    private func renamingChanged(_ editing: Bool) {
        // Top and Left-with-names edit in place; compact Left pops a field out beside the icon.
        if placement != .left {
            panel.allowsKey = editing
            if editing { panel.makeKey() }
            return
        }
        renamePanel?.orderOut(nil)
        renamePanel = nil
        guard editing, let id = model.renaming else { return }
        let strip = ScreenGeometry.cgRect(fromAppKit: panel.frame)
        let layout = model.layout(size: strip.size)
        guard let index = model.tabs.firstIndex(where: { $0.id == id }), let slot = layout.visible.firstIndex(of: index) else { return }
        let icon = layout.frames[slot]
        let frame = CGRect(x: strip.minX + StripLayout.thickness(placement) + 6, y: strip.minY + icon.midY - 15, width: 240, height: 30)
        let field = OverlayPanel(clickThrough: false)
        field.allowsKey = true
        field.setFrame(ScreenGeometry.appKitRect(fromCG: frame), display: false)
        let host = NSHostingView(rootView: LeftRenameField(model: model, tabID: id, actions: actions))
        host.sizingOptions = []
        field.setHostedContent(host)
        field.order(.above, relativeTo: panel.windowNumber)
        resignObservers.append(saveRenameOnResignKey(field))
        field.makeKey()
        renamePanel = field
    }

    /// ⌃⌥R or Rename Tab…: the tab's label becomes a text field.
    func beginRename(_ id: CGWindowID) { model.beginRename(id) }

    var windowNumber: CGWindowID { CGWindowID(panel.windowNumber) }

    func update(tabs: [TabItem], focused: Bool) {
        if model.tabs != tabs {
            withAnimation(Motion.snappy) { model.tabs = tabs }
            model.selection.prune(to: model.order, active: model.activeID)
        }
        if model.focused != focused { model.focused = focused }
    }

    /// Where a drop at this global point would insert, if the point is over the tabs.
    func insertIndex(at cursor: CGPoint) -> Int? {
        let frame = ScreenGeometry.cgRect(fromAppKit: panel.frame)
        let local = CGPoint(x: cursor.x - frame.minX, y: cursor.y - frame.minY)
        guard panel.isVisible, frame.contains(cursor) else { return nil }
        return model.layout(size: frame.size).insertIndex(at: model.along(local), count: model.tabs.count)
    }

    func showInsertion(at index: Int?) {
        guard model.insertion != index else { return }
        withAnimation(Motion.quickFade) { model.insertion = index }
    }

    /// Moves the strip to sit on `content`'s strip edge and orders it above that window.
    func place(content: CGRect, above window: CGWindowID) {
        follow(content: content)
        reorder(above: window)
    }

    /// Frame only (live following during a drag).
    func follow(content: CGRect) {
        let strip = StripLayout.frames(outer: StripLayout.outer(content: content, placement: placement), placement: placement).strip
        panel.setFrame(ScreenGeometry.appKitRect(fromCG: strip), display: true)
        backPanel.setFrame(ScreenGeometry.appKitRect(fromCG: StripLayout.panelFrame(strip: strip, placement: placement)), display: true)
    }

    /// `order(.above, relativeTo:)` plus the settle burst (Phase 0): apps raise their window
    /// 40–50 ms after the focus notification, so for 300 ms check the order once per frame and
    /// fix it whenever the strip isn't directly above. Event-triggered, never idle polling.
    func reorder(above window: CGWindowID) {
        guard !dismissing else { return }
        aboveID = window
        orderBoth()
        burstUntil = ProcessInfo.processInfo.systemUptime + 0.3
        guard burst == nil else { return }
        burst = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let list = ScreenWindows.onScreen().filter { $0.layer == 0 }
                if let target = list.firstIndex(where: { $0.id == self.aboveID }),
                   list.firstIndex(where: { $0.id == CGWindowID(self.backPanel.windowNumber) }) != target - 1
                    || list.firstIndex(where: { $0.id == self.windowNumber }) != target - 2 {
                    self.orderBoth()
                }
                if ProcessInfo.processInfo.systemUptime > self.burstUntil {
                    self.burst?.invalidate()
                    self.burst = nil
                }
            }
        }
    }

    /// Glass directly above the window, the strip directly above the glass.
    private func orderBoth() {
        backPanel.order(.above, relativeTo: Int(aboveID))
        panel.order(.above, relativeTo: backPanel.windowNumber)
    }

    func show() {
        guard !model.visible else { return }
        withAnimation(Motion.smooth) { model.visible = true }
    }

    func hide() {
        withAnimation(Motion.smooth) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.visible else { return }
                self.panel.orderOut(nil)
                self.backPanel.orderOut(nil)
            }
        }
    }

    /// The group dissolved: the strip slides toward its edge and fades (§5.9), then goes away.
    func dismiss() {
        dismissing = true
        burst?.invalidate()
        burst = nil
        renamePanel?.orderOut(nil)
        withAnimation(Motion.smooth) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [panel, backPanel] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                backPanel.orderOut(nil)
            }
        }
    }
}

/// Hosts the SwiftUI strip. Takes the first click without activating anything (the panel is
/// non-activating), tracks the pointer even though Tabsome is never the active app, and turns
/// a middle-click on a tab into Close Tab (§5.7).
private final class StripHostingView: NSHostingView<StripRootView> {
    private let model: TabStripModel
    private let actions: StripActions

    init(model: TabStripModel, actions: StripActions) {
        self.model = model
        self.actions = actions
        super.init(rootView: StripRootView(model: model, actions: actions))
        sizingOptions = []
    }

    @MainActor required init(rootView: StripRootView) { fatalError() }
    @MainActor required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }

    /// The pointer in SwiftUI's coordinates (top-left origin). NSHostingView is already flipped,
    /// so only flip if that ever changes.
    private func flipped(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return isFlipped ? p : CGPoint(x: p.x, y: bounds.height - p.y)
    }

    override func mouseMoved(with event: NSEvent) { model.hover = flipped(event) }

    override func mouseEntered(with event: NSEvent) {
        model.hover = flipped(event)
        model.addCandidates = actions.addCandidates()
    }

    /// Leaving the strip ends the width freeze: tabs reflow (§5.6).
    override func mouseExited(with event: NSEvent) {
        model.hover = nil
        if model.frozenWidth != nil { withAnimation(Motion.smooth) { model.frozenWidth = nil } }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseUp(with: event) }
        let p = flipped(event)
        let layout = model.layout(size: bounds.size)
        guard let i = layout.tab(at: model.along(p)) else { return }
        if model.placement == .top, model.frozenWidth == nil { model.frozenWidth = layout.frames.first?.width }
        actions.close(model.tabs[i].id)
    }
}

/// Top strip or Left column, following the placement setting live (§5.6). No glass here: the
/// back panel draws it, under this one.
struct StripRootView: View {
    let model: TabStripModel
    let actions: StripActions

    var body: some View {
        Group {
            switch model.placement {
            case .top: TabStripView(model: model, actions: actions)
            case .left, .leftNamed: LeftStripView(model: model, actions: actions)
            }
        }
        .modifier(StripAppearance(model: model))
    }
}

/// The strip's glass: one shape for the strip and its corner fillets, in the click-through back panel.
struct StripBackground: View {
    let model: TabStripModel

    var body: some View {
        let shape = StripShape(placement: model.placement, thickness: StripLayout.thickness(model.placement))
        shape.fill(.clear).glassEffect(.regular, in: shape)
            .modifier(StripAppearance(model: model))
            .allowsHitTesting(false)
    }
}

/// Both panels appear and go together: a fade plus a short slide from the strip's edge (§5.9).
private struct StripAppearance: ViewModifier {
    let model: TabStripModel

    func body(content: Content) -> some View {
        content
            .opacity(model.visible ? 1 : 0)
            .offset(x: model.visible || model.placement == .top ? 0 : -6, y: model.visible || model.placement != .top ? 0 : -6)
    }
}
