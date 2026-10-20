import SwiftUI

/// The group's red, yellow, and green buttons (PLAN.md §5.11), drawn to match macOS: Phase 0's
/// measured size, pitch, and inset; all three glyphs appear while the pointer is over any of
/// them. Colors follow the system the way real window buttons do: grey under the Graphite
/// accent, grey when the group isn't the focused window, in Tabsome's Light or Dark scheme.
/// ⌥-click on green does the same as click.
struct WindowControlsView: View {
    let focused: Bool
    let hovered: Bool
    let close: () -> Void
    let minimize: () -> Void
    let zoom: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let graphite = SystemAccessibility.shared.graphiteAccent
        HStack(spacing: Metrics.windowButtonPitch - Metrics.windowButtonDiameter) {
            button(.close, graphite: graphite, glyph: "xmark", label: "Close all tabs", action: close)
            button(.minimize, graphite: graphite, glyph: "minus", label: "Minimize", action: minimize)
            button(.zoom, graphite: graphite, glyph: "arrow.up.left.and.arrow.down.right", label: "Fill", action: zoom)
        }
        .padding(.leading, Metrics.windowButtonLeadingInset)
        .frame(maxHeight: .infinity)
    }

    private func button(_ kind: WindowButtonColors.Kind, graphite: Bool, glyph: String, label: String, action: @escaping () -> Void) -> some View {
        // Like macOS, hovering shows the active colors and glyphs even on an unfocused window.
        let style = WindowButtonColors.style(kind, active: focused || hovered, graphite: graphite, dark: scheme == .dark)
        return Button(action: action) {
            ZStack {
                Circle().fill(style.fill)
                Circle().strokeBorder(style.rim, lineWidth: 0.5)
                if hovered {
                    Image(systemName: glyph)
                        .font(.system(size: glyph.count > 6 ? 7 : 8, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .frame(width: Metrics.windowButtonDiameter, height: Metrics.windowButtonDiameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Window-button colors, measured from real windows on macOS 27 (Finder, and AppKit's own
/// standard buttons in Light and Dark): fills to the pixel; the half-point rims follow the
/// measured direction (darker than the fill in Light, lighter in Dark).
enum WindowButtonColors {
    enum Kind { case close, minimize, zoom }

    static func style(_ kind: Kind, active: Bool, graphite: Bool, dark: Bool) -> (fill: Color, rim: Color) {
        switch (active, graphite) {
        case (false, _):
            return dark ? (hex(0x535353), .white.opacity(0.28)) : (hex(0xF4F5F6), .black.opacity(0.14))
        case (true, true):
            return dark ? (hex(0x939495), .white.opacity(0.4)) : (hex(0xDEDFE0), .black.opacity(0.1))
        case (true, false):
            let fill = switch kind {
            case .close: hex(0xFF5F57)
            case .minimize: hex(0xFEBC2E)
            case .zoom: hex(0x28C840)
            }
            return (fill, .black.opacity(0.12))
        }
    }

    private static func hex(_ v: Int) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
