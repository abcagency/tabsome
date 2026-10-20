import SwiftUI

/// The strip's outline (PLAN.md §5.6): rounded outer corners like a window's, plus two concave
/// fillets that run into the transparent gap outside the window's adjacent rounded corners, so
/// the strip and the window read as one shape with no hard edge at the corners (found in Phase 4).
/// The fillets cover only those corner pixels, which hold no app content.
struct StripShape: Shape {
    let placement: TabPlacement
    /// The strip's thickness (32 pt on top, the column width on the left).
    let thickness: CGFloat
    /// The window's corner radius (Phase 0: 16 pt), for both the outer corners and the fillets.
    var radius: CGFloat = Metrics.windowCornerRadius

    func path(in rect: CGRect) -> Path {
        let t = thickness, r = radius, w = rect.width, h = rect.height
        let k: CGFloat = 0.5523 // cubic Bézier constant for a quarter circle
        var p = Path()
        if placement == .top {
            p.move(to: CGPoint(x: 0, y: t + r))
            p.addLine(to: CGPoint(x: 0, y: r))
            p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
            p.addLine(to: CGPoint(x: w - r, y: 0))
            p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: r), radius: r)
            p.addLine(to: CGPoint(x: w, y: t + r))
            // Right fillet: from the window's right edge up to the strip's bottom edge.
            p.addCurve(to: CGPoint(x: w - r, y: t), control1: CGPoint(x: w, y: t + r - k * r), control2: CGPoint(x: w - r + k * r, y: t))
            p.addLine(to: CGPoint(x: r, y: t))
            // Left fillet.
            p.addCurve(to: CGPoint(x: 0, y: t + r), control1: CGPoint(x: r - k * r, y: t), control2: CGPoint(x: 0, y: t + r - k * r))
        } else {
            p.move(to: CGPoint(x: t + r, y: 0))
            // Top fillet: into the gap outside the window's top-left corner.
            p.addCurve(to: CGPoint(x: t, y: r), control1: CGPoint(x: t + r - k * r, y: 0), control2: CGPoint(x: t, y: r - k * r))
            p.addLine(to: CGPoint(x: t, y: h - r))
            // Bottom fillet.
            p.addCurve(to: CGPoint(x: t + r, y: h), control1: CGPoint(x: t, y: h - r + k * r), control2: CGPoint(x: t + r - k * r, y: h))
            p.addLine(to: CGPoint(x: r, y: h))
            p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)
            p.addLine(to: CGPoint(x: 0, y: r))
            p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
        }
        p.closeSubpath()
        return p
    }
}

extension StripLayout {
    /// The strip panel's frame: the strip plus a band, one corner radius deep, toward the window
    /// for the fillets. The band is transparent apart from the fillets, so clicks there reach the
    /// app's own title bar.
    static func panelFrame(strip: CGRect, placement: TabPlacement) -> CGRect {
        let r = Metrics.windowCornerRadius
        return placement == .top
            ? CGRect(x: strip.minX, y: strip.minY, width: strip.width, height: strip.height + r)
            : CGRect(x: strip.minX, y: strip.minY, width: strip.width + r, height: strip.height)
    }

    /// The strip's own size inside a panel of `panelSize`.
    static func stripSize(panel panelSize: CGSize, placement: TabPlacement) -> CGSize {
        let r = Metrics.windowCornerRadius
        return placement == .top
            ? CGSize(width: panelSize.width, height: panelSize.height - r)
            : CGSize(width: panelSize.width - r, height: panelSize.height)
    }
}
