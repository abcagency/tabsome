import AppKit
import SwiftUI

/// Top-mode strip contents (PLAN.md §5.6, §5.15): the group's window buttons, then the tabs
/// sharing the width (icon-only when narrow, the rest in a » menu), then "+". The active tab is
/// a raised glass capsule; the others sit flat and dimmer, with thin separators. Left mode
/// arrives with the placement setting.
struct TabStripView: View {
    let model: TabStripModel
    let actions: StripActions

    /// A tab being dragged sideways (reorder) or out (tear-out).
    private struct TabDrag {
        let id: CGWindowID
        let startSlot: Int
        var dx: CGFloat = 0
        var tearing = false
    }
    @State private var drag: TabDrag?

    var body: some View {
        GeometryReader { geo in
            let layout = model.layout(width: geo.size.width)
            let slots = slotFrames(layout)
            ZStack(alignment: .topLeading) {
                // Empty strip area: drag to move the group, double-click like a title bar (§5.7).
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { _ in actions.stripDragChanged(mouse()) }
                        .onEnded { _ in actions.stripDragEnded() })
                    .simultaneousGesture(TapGesture(count: 2).onEnded { actions.doubleClicked() })

                WindowControlsView(focused: model.focused, hovered: (model.hover?.x ?? .infinity) < StripLayout.tabsLeadingInset,
                                   close: actions.closeAll, minimize: actions.minimize, zoom: actions.fill)
                    .frame(height: Metrics.topStripHeight)

                ForEach(Array(layout.visible.enumerated()), id: \.element) { slot, index in
                    let tab = model.tabs[index]
                    let frame = slots[tab.id] ?? layout.frames[slot]
                    let isDragged = drag?.id == tab.id && drag?.tearing == false
                    StripTab(tab: tab, style: layout.style,
                             hovered: model.hover.map { frame.contains($0) } ?? false,
                             showsSeparator: separator(after: slot, layout: layout),
                             isLast: index == model.tabs.count - 1, count: model.tabs.count,
                             actions: actions, onClose: { freezeWidths(layout) })
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: isDragged ? layout.frames[drag!.startSlot].minX + drag!.dx : frame.minX)
                        .zIndex(isDragged ? 1 : 0)
                        .gesture(tabGesture(tab: tab, slot: slot, layout: layout))
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                }

                if let x = model.insertion.flatMap(layout.markerX(for:)) {
                    Capsule().fill(Color.accentColor)
                        .frame(width: 3, height: 22)
                        .offset(x: x - 1.5, y: (Metrics.topStripHeight - 22) / 2)
                        .transition(.opacity)
                }

                if let frame = layout.overflowButton {
                    Menu {
                        ForEach(layout.overflow, id: \.self) { i in
                            Button(model.tabs[i].label) { actions.activate(model.tabs[i].id) }
                        }
                    } label: { Image(systemName: "chevron.right.2") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .frame(width: frame.width, height: frame.height).offset(x: frame.minX)
                        .help("More Tabs")
                }

                if let frame = layout.plusButton {
                    Menu {
                        if model.addCandidates.isEmpty { Text("No other windows") }
                        ForEach(model.addCandidates) { c in
                            Button { actions.add(c.id) } label: {
                                Label { Text(c.menuTitle) } icon: { Image(nsImage: menuIcon(c.pid)) }
                            }
                        }
                    } label: { Image(systemName: "plus") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .frame(width: frame.width, height: frame.height).offset(x: frame.minX)
                        .help("Add a Window as a Tab")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: Metrics.windowCornerRadius,
                                                          topTrailingRadius: Metrics.windowCornerRadius, style: .continuous))
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible ? 0 : -6)
    }

    // MARK: Reorder and tear-out (§5.7)

    /// While a tab is dragged sideways, the others take the slots around its provisional spot
    /// (neighbors slide out of the way as it passes their midpoint).
    private func slotFrames(_ layout: StripLayout.TopLayout) -> [CGWindowID: CGRect] {
        guard let drag, !drag.tearing, let width = layout.frames.first?.width, width > 0 else { return [:] }
        let ids = layout.visible.map { model.tabs[$0].id }
        var order = ids.filter { $0 != drag.id }
        order.insert(drag.id, at: provisionalSlot(drag, layout))
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, layout.frames[$0.offset]) })
    }

    private func provisionalSlot(_ drag: TabDrag, _ layout: StripLayout.TopLayout) -> Int {
        guard let width = layout.frames.first?.width, width > 0 else { return drag.startSlot }
        let center = layout.frames[drag.startSlot].midX + drag.dx
        return min(max(Int((center - StripLayout.tabsLeadingInset) / width), 0), layout.visible.count - 1)
    }

    private func tabGesture(tab: TabItem, slot: Int, layout: StripLayout.TopLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag?.id != tab.id {
                    drag = TabDrag(id: tab.id, startSlot: slot)
                    actions.activate(tab.id) // like Safari, a tab switches on mouse down
                }
                guard var d = drag else { return }
                // Tear out: more than 20 pt away from the strip (§5.7).
                if !d.tearing, abs(value.translation.height) > 20 {
                    d.tearing = true
                    drag = d
                    actions.tearOffBegan(tab.id, mouse())
                }
                if d.tearing {
                    actions.tearOffMoved(mouse())
                } else {
                    withAnimation(Motion.snappy) { drag?.dx = value.translation.width }
                }
            }
            .onEnded { value in
                guard let d = drag else { return }
                drag = nil
                if d.tearing {
                    if abs(value.translation.height) > 20 { actions.tearOffEnded(mouse()) } else { actions.tearOffCancelled() }
                } else if abs(d.dx) > 4 {
                    let target = provisionalSlot(d, layout)
                    if target != d.startSlot { withAnimation(Motion.snappy) { actions.reorder(tab.id, layout.visible.sorted()[target]) } }
                }
            }
    }

    private func separator(after slot: Int, layout: StripLayout.TopLayout) -> Bool {
        guard slot + 1 < layout.visible.count else { return false }
        return !model.tabs[layout.visible[slot]].isActive && !model.tabs[layout.visible[slot + 1]].isActive
    }

    private func freezeWidths(_ layout: StripLayout.TopLayout) {
        if model.frozenWidth == nil { model.frozenWidth = layout.frames.first?.width }
    }
}

/// Global, top-left-origin pointer location.
@MainActor
private func mouse() -> CGPoint { ScreenGeometry.cgPoint(fromAppKit: NSEvent.mouseLocation) }

/// A 16 pt copy of an app's icon for menus.
@MainActor
private func menuIcon(_ pid: pid_t) -> NSImage {
    let icon = (NSRunningApplication(processIdentifier: pid)?.icon?.copy() as? NSImage) ?? NSImage()
    icon.size = NSSize(width: 16, height: 16)
    return icon
}

private struct StripTab: View {
    let tab: TabItem
    let style: StripLayout.TopLayout.Style
    let hovered: Bool
    let showsSeparator: Bool
    let isLast: Bool
    let count: Int
    let actions: StripActions
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if style == .iconOnly, tab.isActive, hovered {
                closeButton // narrow tabs: the active one trades its icon for × on hover (Chrome)
            } else if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            if style == .full {
                Text(tab.label)
                    .font(.system(size: 12, weight: tab.isActive ? .medium : .regular))
                    .foregroundStyle(tab.isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                // Chrome's rule: always on the active tab, on hover for the others.
                closeButton
                    .opacity(tab.isActive || hovered ? 1 : 0)
                    .animation(Motion.quickFade, value: hovered)
            }
        }
        .padding(.horizontal, style == .full ? 10 : 0)
        .frame(maxWidth: .infinity, maxHeight: 26)
        .background {
            if tab.isActive {
                Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
            } else if hovered {
                Capsule().fill(Color.primary.opacity(0.06))
            }
        }
        .overlay(alignment: .trailing) {
            if showsSeparator {
                Rectangle().fill(.separator).frame(width: 1, height: 14).offset(x: 0.5)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .help(tab.title ?? tab.label)
        // Chrome's order (§5.7). Rename arrives with inline renaming.
        .contextMenu {
            Button("Close Tab") { onClose(); actions.close(tab.id) }
            Button("Close Other Tabs") { actions.closeOthers(tab.id) }.disabled(count < 2)
            Button("Close Tabs to the Right") { actions.closeToTheRight(tab.id) }.disabled(isLast)
            Divider()
            Button("Move Tab to New Window") { actions.moveToNewWindow(tab.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(tab.isActive ? [.isSelected, .isButton] : .isButton)
    }

    private var closeButton: some View {
        Button { onClose(); actions.close(tab.id) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Close \(tab.label)")
    }
}
