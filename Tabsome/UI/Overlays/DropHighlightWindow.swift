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

    func show(targetFrame: CGRect, above target: CGWindowID, tabs: [GhostTab]) {
        hideGeneration += 1
        let strip = Metrics.topStripHeight
        let m = Self.margin
        let outer = CGRect(x: targetFrame.minX - m, y: targetFrame.minY - strip - m,
                           width: targetFrame.width + 2 * m, height: targetFrame.height + strip + 2 * m)
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
}

private struct DropHighlightView: View {
    let model: DropHighlightModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.windowCornerRadius, style: .continuous)
        VStack(spacing: 0) {
            GhostStrip(tabs: model.tabs)
                .frame(height: Metrics.topStripHeight)
            shape
                .fill(Color.accentColor.opacity(0.12))
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.25)), in: shape)
                .overlay(shape.strokeBorder(Color.accentColor.opacity(contrast == .increased ? 0.95 : 0.6), lineWidth: contrast == .increased ? 3 : 2))
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
