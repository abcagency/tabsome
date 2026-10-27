import AppKit
import SwiftUI

/// Left-mode strip (PLAN.md §5.6): a 40 pt column of 28 pt app icons, no text. The active tab
/// gets a highlight pill behind its icon and an accent bar on the inner edge; × appears as a
/// badge on the icon's corner on hover; the tooltip is the tab's label and window title. Tabs
/// reorder up and down and tear out to the right. There are no window buttons here: right-click
/// the empty column for Close All Tabs, Minimize, and Fill (§5.11, §10.5).
struct LeftStripView: View {
    let model: TabStripModel
    let actions: StripActions

    private struct TabDrag {
        let id: CGWindowID
        let startSlot: Int
        let modifier: TabSelection.Modifier
        var dy: CGFloat = 0
        var tearing = false
    }
    @State private var drag: TabDrag?

    var body: some View {
        GeometryReader { geo in
            let layout = model.layout(size: geo.size)
            let slots = slotFrames(layout)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { _ in actions.stripDragChanged(mouse()) }
                        .onEnded { _ in actions.stripDragEnded() })
                    .simultaneousGesture(TapGesture(count: 2).onEnded { actions.doubleClicked() })
                    .contextMenu {
                        Button("Close All Tabs") { actions.closeAll() }
                        Button("Minimize") { actions.minimize() }
                        Button("Fill") { actions.fill() }
                    }

                ForEach(Array(layout.visible.enumerated()), id: \.element) { slot, index in
                    let tab = model.tabs[index]
                    let frame = slots[tab.id] ?? layout.frames[slot]
                    let isDragged = drag?.id == tab.id && drag?.tearing == false
                    let hovered = model.hover.map { frame.contains($0) } ?? false
                    Group {
                        if model.placement == .leftNamed {
                            NamedLeftTab(tab: tab, hovered: hovered, model: model, actions: actions)
                        } else {
                            LeftTab(tab: tab, hovered: hovered, model: model, actions: actions)
                        }
                    }
                    .modifier(LeftTabMenu(tab: tab, isLast: index == model.tabs.count - 1, count: model.tabs.count, model: model, actions: actions))
                        .frame(width: frame.width, height: frame.height)
                        .offset(y: isDragged ? layout.frames[drag!.startSlot].minY + drag!.dy : frame.minY)
                        .zIndex(isDragged ? 1 : 0)
                        .gesture(tabGesture(tab: tab, slot: slot, layout: layout))
                        .simultaneousGesture(TapGesture(count: 2).onEnded { model.beginRename(tab.id) })
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }

                if let y = model.insertion.flatMap(layout.markerPosition(for:)) {
                    let w = StripLayout.thickness(model.placement, size: model.options.size) - 14
                    Capsule().fill(Color.accentColor)
                        .frame(width: w, height: 3)
                        .offset(x: 7, y: y - 1.5)
                        .transition(.opacity)
                }

                if let frame = layout.overflowButton {
                    Menu {
                        ForEach(layout.overflow, id: \.self) { i in
                            Button(model.tabs[i].label) { actions.activate(model.tabs[i].id) }
                        }
                    } label: { Image(systemName: "chevron.down.2") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .frame(width: frame.width, height: frame.height).offset(y: frame.minY)
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
                        .frame(width: frame.width, height: frame.height).offset(y: frame.minY)
                        .help("Add a Window as a Tab")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func slotFrames(_ layout: StripLayout.TabsLayout) -> [CGWindowID: CGRect] {
        guard let drag, !drag.tearing, layout.slotLength > 0 else { return [:] }
        var order = layout.visible.map { model.tabs[$0].id }.filter { $0 != drag.id }
        order.insert(drag.id, at: provisionalSlot(drag, layout))
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, layout.frames[$0.offset]) })
    }

    private func provisionalSlot(_ drag: TabDrag, _ layout: StripLayout.TabsLayout) -> Int {
        guard layout.slotLength > 0 else { return drag.startSlot }
        let center = layout.frames[drag.startSlot].midY + drag.dy
        return min(max(Int((center - StripLayout.leftTopInset) / layout.slotLength), 0), layout.visible.count - 1)
    }

    /// Up and down reorders; more than 20 pt to the right tears the tab out (§5.7).
    private func tabGesture(tab: TabItem, slot: Int, layout: StripLayout.TabsLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag?.id != tab.id {
                    if model.renaming != nil, model.renaming != tab.id { model.commitRename(refocus: false) }
                    drag = TabDrag(id: tab.id, startSlot: slot, modifier: pressModifier())
                    if model.selection.click(tab.id, modifier: drag!.modifier, order: model.order, active: model.activeID) {
                        actions.activate(tab.id)
                    }
                }
                guard var d = drag else { return }
                if !d.tearing, abs(value.translation.width) > 20 {
                    d.tearing = true
                    drag = d
                    actions.tearOffBegan(model.selectedTabs(including: tab.id), tab.id, mouse())
                }
                if d.tearing {
                    actions.tearOffMoved(mouse())
                } else {
                    withAnimation(Motion.snappy) { drag?.dy = value.translation.height }
                }
            }
            .onEnded { value in
                guard let d = drag else { return }
                drag = nil
                if d.tearing {
                    if abs(value.translation.width) > 20 { actions.tearOffEnded(mouse()) } else { actions.tearOffCancelled() }
                } else if abs(d.dy) > 4 {
                    let target = provisionalSlot(d, layout)
                    if target != d.startSlot { withAnimation(Motion.snappy) { actions.reorder(tab.id, layout.visible.sorted()[target]) } }
                } else if d.modifier == .none {
                    model.selection.collapse(to: tab.id)
                }
            }
    }
}

/// Compact Left: just the icon.
private struct LeftTab: View {
    let tab: TabItem
    let hovered: Bool
    let model: TabStripModel
    let actions: StripActions

    private var isSelected: Bool { model.selection.count > 1 && model.selection.selected.contains(tab.id) }

    var body: some View {
        ZStack {
            if isSelected, !tab.isActive {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.16)).padding(3)
            }
            if tab.isActive {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(3)
            } else if model.springFlash == tab.id {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.35)).padding(3)
            } else if hovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)).padding(3)
            }
            if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                Image(nsImage: icon).resizable()
                    .frame(width: StripLayout.leftIconSize(model.options.size), height: StripLayout.leftIconSize(model.options.size))
                    .opacity(tab.isActive || hovered ? 1 : 0.75)
            }
            if hovered, model.options.showsCloseButtons {
                Button { actions.close(tab.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 13, height: 13)
                        .background(.regularMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(4)
                .accessibilityLabel("Close \(tab.label)")
                .transition(.opacity)
            }
        }
        .overlay(alignment: .trailing) {
            if tab.isActive {
                Capsule().fill(Color.accentColor).frame(width: 3, height: 20) // the accent bar, inner edge
            }
        }
        .animation(Motion.quickFade, value: hovered)
        .contentShape(Rectangle())
        .help(model.tooltip(tab, tab.title.map { "\(tab.label)\n\($0)" } ?? tab.label))
    }
}

/// Left with names: icon, name (ellipsis when long), × on the active tab and on hover.
private struct NamedLeftTab: View {
    let tab: TabItem
    let hovered: Bool
    let model: TabStripModel
    let actions: StripActions

    private var isSelected: Bool { model.selection.count > 1 && model.selection.selected.contains(tab.id) }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                Image(nsImage: icon).resizable()
                    .frame(width: StripLayout.leftNamedIconSize, height: StripLayout.leftNamedIconSize)
            }
            if model.renaming == tab.id {
                RenameTextField(model: model, tab: tab, actions: actions)
            } else {
                Text(tab.label)
                    .font(.system(size: 12, weight: tab.isActive ? .medium : .regular))
                    .foregroundStyle(tab.isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if model.options.showsCloseButtons {
                    Button { actions.close(tab.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(tab.isActive || hovered ? 1 : 0)
                    .accessibilityLabel("Close \(tab.label)")
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            if tab.isActive {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            } else if model.springFlash == tab.id {
                shape.fill(Color.accentColor.opacity(0.35))
            } else if isSelected {
                shape.fill(Color.accentColor.opacity(0.16))
            } else if hovered {
                shape.fill(Color.primary.opacity(0.06))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(alignment: .trailing) {
            if tab.isActive { Capsule().fill(Color.accentColor).frame(width: 3, height: 18) }
        }
        .animation(Motion.quickFade, value: hovered)
        .contentShape(Rectangle())
        .help(model.tooltip(tab, tab.title.map { "\(tab.label)\n\($0)" } ?? tab.label))
    }
}

/// The tab menu in Left mode: Chrome's order, with "to the right" read as "below" (§5.6).
private struct LeftTabMenu: ViewModifier {
    let tab: TabItem
    let isLast: Bool
    let count: Int
    let model: TabStripModel
    let actions: StripActions

    func body(content: Content) -> some View {
        let isSelected = model.selection.count > 1 && model.selection.selected.contains(tab.id)
        let selectedIDs = model.selectedTabs(including: tab.id)
        content
            .contextMenu {
                if isSelected {
                    Button("Close \(selectedIDs.count) Tabs") { actions.closeTabs(selectedIDs) }
                } else {
                    Button("Close Tab") { actions.close(tab.id) }
                }
                Button("Close Other Tabs") { actions.closeOthers(tab.id) }.disabled(count < 2)
                Button("Close Tabs Below") { actions.closeToTheRight(tab.id) }.disabled(isLast)
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
