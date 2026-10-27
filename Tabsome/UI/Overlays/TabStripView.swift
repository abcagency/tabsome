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
        let modifier: TabSelection.Modifier
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
                    .frame(height: StripLayout.thickness(.top, size: model.options.size))

                ForEach(Array(layout.visible.enumerated()), id: \.element) { slot, index in
                    let tab = model.tabs[index]
                    let frame = slots[tab.id] ?? layout.frames[slot]
                    let isDragged = drag?.id == tab.id && drag?.tearing == false
                    StripTab(tab: tab, style: layout.style,
                             hovered: model.hover.map { frame.contains($0) } ?? false,
                             showsSeparator: separator(after: slot, layout: layout),
                             isLast: index == model.tabs.count - 1, count: model.tabs.count,
                             model: model, actions: actions, onClose: { freezeWidths(layout) })
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: isDragged ? layout.frames[drag!.startSlot].minX + drag!.dx : frame.minX)
                        .zIndex(isDragged ? 1 : 0)
                        .gesture(tabGesture(tab: tab, slot: slot, layout: layout))
                        // Double-click renames (§5.10); the first click has already switched tabs.
                        .simultaneousGesture(TapGesture(count: 2).onEnded { model.beginRename(tab.id) })
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                }

                if let x = model.insertion.flatMap(layout.markerPosition(for:)) {
                    Capsule().fill(Color.accentColor)
                        .frame(width: 3, height: 22)
                        .offset(x: x - 1.5, y: (StripLayout.thickness(.top, size: model.options.size) - 22) / 2)
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
    }

    // MARK: Reorder and tear-out (§5.7)

    /// While a tab is dragged sideways, the others take the slots around its provisional spot
    /// (neighbors slide out of the way as it passes their midpoint).
    private func slotFrames(_ layout: StripLayout.TabsLayout) -> [CGWindowID: CGRect] {
        guard let drag, !drag.tearing, let width = layout.frames.first?.width, width > 0 else { return [:] }
        let ids = layout.visible.map { model.tabs[$0].id }
        var order = ids.filter { $0 != drag.id }
        order.insert(drag.id, at: provisionalSlot(drag, layout))
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, layout.frames[$0.offset]) })
    }

    private func provisionalSlot(_ drag: TabDrag, _ layout: StripLayout.TabsLayout) -> Int {
        guard let width = layout.frames.first?.width, width > 0 else { return drag.startSlot }
        let center = layout.frames[drag.startSlot].midX + drag.dx
        return min(max(Int((center - StripLayout.tabsLeadingInset) / width), 0), layout.visible.count - 1)
    }

    private func tabGesture(tab: TabItem, slot: Int, layout: StripLayout.TabsLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag?.id != tab.id {
                    if model.renaming != nil, model.renaming != tab.id { model.commitRename(refocus: false) }
                    drag = TabDrag(id: tab.id, startSlot: slot, modifier: pressModifier())
                    // Like Safari, a tab switches on mouse down; ⇧/⌘ change the selection (§5.7).
                    if model.selection.click(tab.id, modifier: drag!.modifier, order: model.order, active: model.activeID) {
                        actions.activate(tab.id)
                    }
                }
                guard var d = drag else { return }
                // Tear out: more than 20 pt away from the strip (§5.7), with any selected tabs.
                if !d.tearing, abs(value.translation.height) > 20 {
                    d.tearing = true
                    drag = d
                    actions.tearOffBegan(model.selectedTabs(including: tab.id), tab.id, mouse())
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
                } else if d.modifier == .none {
                    model.selection.collapse(to: tab.id) // a plain click without a drag: just this tab
                }
            }
    }

    private func separator(after slot: Int, layout: StripLayout.TabsLayout) -> Bool {
        guard slot + 1 < layout.visible.count else { return false }
        return !model.tabs[layout.visible[slot]].isActive && !model.tabs[layout.visible[slot + 1]].isActive
    }

    private func freezeWidths(_ layout: StripLayout.TabsLayout) {
        if model.frozenWidth == nil { model.frozenWidth = layout.frames.first?.width }
    }
}

/// Global, top-left-origin pointer location.
@MainActor
private func mouse() -> CGPoint { ScreenGeometry.cgPoint(fromAppKit: NSEvent.mouseLocation) }

/// ⇧ or ⌘ held when a tab is pressed (§5.7).
@MainActor
func pressModifier() -> TabSelection.Modifier {
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift) { return .shift }
    if flags.contains(.command) { return .command }
    return .none
}

/// A 16 pt copy of an app's icon for menus.
@MainActor
private func menuIcon(_ pid: pid_t) -> NSImage {
    let icon = (NSRunningApplication(processIdentifier: pid)?.icon?.copy() as? NSImage) ?? NSImage()
    icon.size = NSSize(width: 16, height: 16)
    return icon
}

private struct StripTab: View {
    let tab: TabItem
    let style: StripLayout.TabsLayout.Style
    let hovered: Bool
    let showsSeparator: Bool
    let isLast: Bool
    let count: Int
    let model: TabStripModel
    let actions: StripActions
    let onClose: () -> Void

    private var isRenaming: Bool { model.renaming == tab.id }
    private var isSelected: Bool { model.selection.count > 1 && model.selection.selected.contains(tab.id) }
    private var selectedIDs: [CGWindowID] { model.selectedTabs(including: tab.id) }

    var body: some View {
        HStack(spacing: 6) {
            if isRenaming {
                if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                renameField
            } else if style == .iconOnly, tab.isActive, hovered, model.options.showsCloseButtons {
                closeButton // narrow tabs: the active one trades its icon for × on hover (Chrome)
            } else if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            if style == .full, !isRenaming {
                Text(tab.label)
                    .font(.system(size: 12, weight: tab.isActive ? .medium : .regular))
                    .foregroundStyle(tab.isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                // Chrome's rule: always on the active tab, on hover for the others.
                if model.options.showsCloseButtons {
                    closeButton
                        .opacity(tab.isActive || hovered ? 1 : 0)
                        .animation(Motion.quickFade, value: hovered)
                }
            }
        }
        .padding(.horizontal, style == .full ? 10 : 0)
        .frame(maxWidth: .infinity, maxHeight: StripLayout.thickness(.top, size: model.options.size) - 6)
        .background {
            if tab.isActive {
                Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
            } else if model.springFlash == tab.id {
                Capsule().fill(Color.accentColor.opacity(0.35)) // the blink before a spring-loaded switch
            } else if isSelected {
                Capsule().fill(Color.accentColor.opacity(0.16))
            } else if hovered {
                Capsule().fill(Color.primary.opacity(0.06))
            }
        }
        .overlay(alignment: .trailing) {
            if showsSeparator, !isSelected {
                Rectangle().fill(.separator).frame(width: 1, height: 14).offset(x: 0.5)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .help(model.tooltip(tab, tab.title ?? tab.label))
        // Chrome's order (§5.7). Rename arrives with inline renaming.
        .contextMenu {
            if isSelected {
                Button("Close \(selectedIDs.count) Tabs") { onClose(); actions.closeTabs(selectedIDs) }
            } else {
                Button("Close Tab") { onClose(); actions.close(tab.id) }
            }
            Button("Close Other Tabs") { actions.closeOthers(tab.id) }.disabled(count < 2)
            Button("Close Tabs to the Right") { actions.closeToTheRight(tab.id) }.disabled(isLast)
            Divider()
            Button(isSelected ? "Move \(selectedIDs.count) Tabs to New Window" : "Move Tab to New Window") {
                actions.moveToNewWindow(selectedIDs, tab.id)
            }
            Divider()
            Button("Rename Tab…") { model.beginRename(tab.id) }
            if tab.isRenamed { Button("Reset Name") { actions.rename(tab.id, nil, true) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(tab.isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// The label becomes a field at the same font and place (§5.10).
    private var renameField: some View {
        RenameTextField(model: model, tab: tab, actions: actions)
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
