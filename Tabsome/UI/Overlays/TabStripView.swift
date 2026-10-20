import AppKit
import SwiftUI

/// Top-mode strip contents (PLAN.md §5.6, §5.15): the group's window buttons, then the tabs
/// sharing the width evenly. The active tab is a raised glass capsule; the others sit flat and
/// dimmer, with thin separators. Left mode arrives in Phase 4.
struct TabStripView: View {
    let model: TabStripModel
    let actions: StripActions

    var body: some View {
        GeometryReader { geo in
            let frames = StripLayout.tabFrames(stripWidth: geo.size.width, count: model.tabs.count)
            ZStack(alignment: .topLeading) {
                // Empty strip area: dragging it moves the whole group (§5.7).
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { _ in actions.stripDragChanged(mouse()) }
                        .onEnded { _ in actions.stripDragEnded() })

                WindowControlsView(focused: model.focused, hovered: (model.hover?.x ?? .infinity) < StripLayout.tabsLeadingInset,
                                   close: actions.closeAll, minimize: actions.minimize, zoom: actions.fill)
                    .frame(height: Metrics.topStripHeight)

                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                    let frame = frames[index]
                    let next = index + 1 < model.tabs.count ? model.tabs[index + 1] : nil
                    StripTab(tab: tab, hovered: model.hover.map { frame.contains($0) } ?? false,
                            showsSeparator: !tab.isActive && next.map { !$0.isActive } ?? false, actions: actions)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: Metrics.windowCornerRadius,
                                                          topTrailingRadius: Metrics.windowCornerRadius, style: .continuous))
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible ? 0 : -6)
        .animation(Motion.smooth, value: model.tabs.map(\.id))
    }
}

/// Global, top-left-origin pointer location.
@MainActor
private func mouse() -> CGPoint { ScreenGeometry.cgPoint(fromAppKit: NSEvent.mouseLocation) }

private struct StripTab: View {
    let tab: TabItem
    let hovered: Bool
    let showsSeparator: Bool
    let actions: StripActions
    @State private var pressed = false
    @State private var tearing = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(tab.label)
                .font(.system(size: 12, weight: tab.isActive ? .medium : .regular))
                .foregroundStyle(tab.isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            // Chrome's rule: always on the active tab, on hover for the others.
            Button { actions.close(tab.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(tab.isActive || hovered ? 1 : 0)
            .animation(Motion.quickFade, value: hovered)
            .accessibilityLabel("Close \(tab.label)")
        }
        .padding(.horizontal, 10)
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
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressed {
                    pressed = true
                    actions.activate(tab.id) // like Safari, a tab switches on mouse down
                }
                // Tear out: more than 20 pt away from the strip (§5.7).
                if !tearing, abs(value.translation.height) > 20 {
                    tearing = true
                    actions.tearOffBegan(tab.id, mouse())
                }
                if tearing { actions.tearOffMoved(mouse()) }
            }
            .onEnded { value in
                if tearing {
                    if abs(value.translation.height) > 20 { actions.tearOffEnded(mouse()) } else { actions.tearOffCancelled() }
                }
                pressed = false
                tearing = false
            })
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(tab.isActive ? [.isSelected, .isButton] : .isButton)
    }
}
