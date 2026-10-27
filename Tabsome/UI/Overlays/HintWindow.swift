import AppKit
import SwiftUI

/// The first-time hint's label (PLAN.md §7 Phase 6): a small glass capsule just below and right
/// of the cursor, above the window being dragged. It ignores the mouse (S7) and VoiceOver.
@MainActor
final class HintWindow {
    private let panel = OverlayPanel(clickThrough: true)
    private let model = HintModel()
    private let host: NSHostingView<HintLabel>

    init() {
        panel.level = .floating
        host = NSHostingView(rootView: HintLabel(model: model))
        host.sizingOptions = []
        panel.setHostedContent(host)
    }

    /// Shows `text` by the cursor (global, top-left origin), or moves it there if it's showing.
    func show(_ text: String, at cursor: CGPoint) {
        model.text = text
        let size = host.fittingSize
        let origin = CGPoint(x: cursor.x + 14, y: cursor.y + 20)
        panel.setFrame(ScreenGeometry.appKitRect(fromCG: CGRect(origin: origin, size: size)), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

@MainActor
@Observable
private final class HintModel {
    var text = ""
}

private struct HintLabel: View {
    let model: HintModel

    var body: some View {
        Text(model.text)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
            .padding(4) // room for the glass edge
            .fixedSize()
            .accessibilityHidden(true)
    }
}
