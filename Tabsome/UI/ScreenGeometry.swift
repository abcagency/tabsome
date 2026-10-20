import AppKit

/// Converts between the two global coordinate spaces: CGWindowList/AX (top-left origin of the
/// primary display, y down) and AppKit (bottom-left origin, y up).
@MainActor
enum ScreenGeometry {
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cgPoint(fromAppKit p: NSPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func cgRect(fromAppKit r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func appKitRect(fromCG r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
