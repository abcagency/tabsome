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
    var tearOffBegan: (CGWindowID, CGPoint) -> Void
    var tearOffMoved: (CGPoint) -> Void
    var tearOffEnded: (CGPoint) -> Void
    var tearOffCancelled: () -> Void
    var stripDragChanged: (CGPoint) -> Void
    var stripDragEnded: () -> Void
    var reorder: (CGWindowID, Int) -> Void
    var closeOthers: (CGWindowID) -> Void
    var closeToTheRight: (CGWindowID) -> Void
    var moveToNewWindow: (CGWindowID) -> Void
    var addCandidates: () -> [AddCandidate]
    var add: (CGWindowID) -> Void
    var doubleClicked: () -> Void
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

    var activeIndex: Int { tabs.firstIndex(where: \.isActive) ?? 0 }
    /// The quiet 50-tab limit (§1): a full strip has no "+".
    var canAdd: Bool { tabs.count < TabGroup.maxTabs }

    func layout(width: CGFloat) -> StripLayout.TopLayout {
        StripLayout.top(width: width, count: tabs.count, active: activeIndex, showsPlus: canAdd, frozenWidth: frozenWidth)
    }
}

/// The tab strip overlay (PLAN.md §5.6): one non-activating panel per group, at normal level,
/// kept directly above the group's active window.
@MainActor
final class TabBarWindow {
    private let panel = OverlayPanel(clickThrough: false)
    private let model = TabStripModel()
    private var burst: Timer?
    private var burstUntil: TimeInterval = 0
    private var aboveID: CGWindowID = 0
    private var dismissing = false
    var placement: TabPlacement = .top

    init(actions: StripActions) {
        panel.setHostedContent(StripHostingView(model: model, actions: actions))
    }

    var windowNumber: CGWindowID { CGWindowID(panel.windowNumber) }

    func update(tabs: [TabItem], focused: Bool) {
        if model.tabs != tabs {
            withAnimation(Motion.snappy) { model.tabs = tabs }
        }
        if model.focused != focused { model.focused = focused }
    }

    /// Where a drop at this global point would insert, if the point is over the tabs.
    func insertIndex(at cursor: CGPoint) -> Int? {
        let frame = ScreenGeometry.cgRect(fromAppKit: panel.frame)
        guard panel.isVisible, frame.contains(cursor) else { return nil }
        return model.layout(width: frame.width).insertIndex(at: cursor.x - frame.minX, count: model.tabs.count)
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
    }

    /// `order(.above, relativeTo:)` plus the settle burst (Phase 0): apps raise their window
    /// 40–50 ms after the focus notification, so for 300 ms check the order once per frame and
    /// fix it whenever the strip isn't directly above. Event-triggered, never idle polling.
    func reorder(above window: CGWindowID) {
        guard !dismissing else { return }
        aboveID = window
        panel.order(.above, relativeTo: Int(window))
        burstUntil = ProcessInfo.processInfo.systemUptime + 0.3
        guard burst == nil else { return }
        burst = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let list = ScreenWindows.onScreen().filter { $0.layer == 0 }
                if let target = list.firstIndex(where: { $0.id == self.aboveID }),
                   list.firstIndex(where: { $0.id == self.windowNumber }) != target - 1 {
                    self.panel.order(.above, relativeTo: Int(self.aboveID))
                }
                if ProcessInfo.processInfo.systemUptime > self.burstUntil {
                    self.burst?.invalidate()
                    self.burst = nil
                }
            }
        }
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
            }
        }
    }

    /// The group dissolved: the strip slides toward its edge and fades (§5.9), then goes away.
    func dismiss() {
        dismissing = true
        burst?.invalidate()
        burst = nil
        withAnimation(Motion.smooth) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }
}

/// Hosts the SwiftUI strip. Takes the first click without activating anything (the panel is
/// non-activating), tracks the pointer even though Tabsome is never the active app, and turns
/// a middle-click on a tab into Close Tab (§5.7).
private final class StripHostingView: NSHostingView<TabStripView> {
    private let model: TabStripModel
    private let actions: StripActions

    init(model: TabStripModel, actions: StripActions) {
        self.model = model
        self.actions = actions
        super.init(rootView: TabStripView(model: model, actions: actions))
        sizingOptions = []
    }

    @MainActor required init(rootView: TabStripView) { fatalError() }
    @MainActor required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }

    private func flipped(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: bounds.height - p.y)
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
        let layout = model.layout(width: bounds.width)
        guard let i = layout.tab(at: p.x) else { return }
        if model.frozenWidth == nil { model.frozenWidth = layout.frames.first?.width }
        actions.close(model.tabs[i].id)
    }
}
