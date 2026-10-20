import AppKit
import SwiftUI

/// "Drop here to tab" (PLAN.md §5.3, §5.9, §5.15): a translucent glass rounded rect over the
/// target with the accent color, like the macOS window-tiling preview, plus a ghost tab strip
/// above it previewing the result. It fades and scales in (0.97 → 1.0) and sits directly
/// above the target, so the dragged window stays in front of it.
@MainActor
final class DropHighlightWindow {
    private let panel = OverlayPanel(clickThrough: true)
    private let model = DropHighlightModel()
    private var hideGeneration = 0

    /// Room around the target for the scale-in and the glow.
    private static let margin: CGFloat = 12

    init() {
        let host = NSHostingView(rootView: DropHighlightView(model: model))
        host.sizingOptions = []
        panel.setHostedContent(host)
    }

    func show(targetFrame: CGRect, above target: CGWindowID, tabs: [GhostTab], placement: TabPlacement = .top) {
        hideGeneration += 1
        let m = Self.margin
        let withStrip = StripLayout.outer(content: targetFrame, placement: placement)
        let outer = withStrip.insetBy(dx: -m, dy: -m)
        model.placement = placement
        panel.setFrame(ScreenGeometry.appKitRect(fromCG: outer), display: false)
        model.tabs = tabs
        model.margin = m
        model.visible = false
        panel.order(.above, relativeTo: Int(target))
        withAnimation(Motion.quickFade) { model.visible = true }
    }

    func hide() {
        guard panel.isVisible else { return }
        withAnimation(Motion.quickFade) { model.visible = false }
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

@MainActor
@Observable
final class DropHighlightModel {
    var visible = false
    var tabs: [GhostTab] = []
    var margin: CGFloat = 0
    var placement: TabPlacement = .top
}

private struct DropHighlightView: View {
    let model: DropHighlightModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.windowCornerRadius, style: .continuous)
        let highlight = shape
            .fill(Color.accentColor.opacity(0.12))
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.25)), in: shape)
            .overlay(shape.strokeBorder(Color.accentColor.opacity(contrast == .increased ? 0.95 : 0.6), lineWidth: contrast == .increased ? 3 : 2))
        Group {
            if model.placement == .top {
                VStack(spacing: 0) {
                    GhostStrip(tabs: model.tabs).frame(height: Metrics.topStripHeight)
                    highlight
                }
            } else {
                HStack(spacing: 0) {
                    GhostColumn(tabs: model.tabs, named: model.placement == .leftNamed)
                        .frame(width: StripLayout.thickness(model.placement))
                    highlight
                }
            }
        }
        .padding(model.margin)
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(model.visible ? 1 : 0.97)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The preview of the strip the group will get: window buttons (inactive), then the tabs.
private struct GhostStrip: View {
    let tabs: [GhostTab]

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: Metrics.windowButtonPitch - Metrics.windowButtonDiameter) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.tertiary).frame(width: Metrics.windowButtonDiameter, height: Metrics.windowButtonDiameter)
                }
            }
            .padding(.leading, Metrics.windowButtonLeadingInset - 3)
            .padding(.trailing, 6)
            ForEach(tabs) { tab in
                GhostTabView(tab: tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: Metrics.windowCornerRadius, topTrailingRadius: Metrics.windowCornerRadius, style: .continuous))
    }
}

/// Left mode's preview: the icon column the group will get.
private struct GhostColumn: View {
    let tabs: [GhostTab]
    let named: Bool

    var body: some View {
        let icon = named ? StripLayout.leftNamedIconSize : StripLayout.leftIconSize
        VStack(spacing: named ? 4 : StripLayout.leftSlotHeight - StripLayout.leftIconSize) {
            ForEach(tabs) { tab in
                HStack(spacing: 6) {
                    if let image = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                        Image(nsImage: image).resizable().frame(width: icon, height: icon)
                    }
                    if named {
                        Text(tab.label).font(.system(size: 12, weight: tab.isNew ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
                .padding(named ? 6 : 3)
                .background {
                    if tab.isNew { RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.2)) }
                }
                .padding(.horizontal, named ? 6 : 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, StripLayout.leftTopInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: Metrics.windowCornerRadius, bottomLeadingRadius: Metrics.windowCornerRadius, style: .continuous))
    }
}

private struct GhostTabView: View {
    let tab: GhostTab

    var body: some View {
        HStack(spacing: 6) {
            if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(tab.label)
                .font(.system(size: 12, weight: tab.isNew ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 90, maxWidth: 220, minHeight: 24)
        .background {
            if tab.isNew {
                Capsule().fill(Color.accentColor.opacity(0.18))
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.3)), in: Capsule())
            }
        }
    }
}
