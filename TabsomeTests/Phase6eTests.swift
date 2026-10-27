import CoreGraphics
import Testing
@testable import Tabsome

/// The motion pass (PLAN.md §7 Phase 6e): the checks that decide what a proxy shows, on
/// made-up captures.
struct ProxyPictureTests {
    /// A 40×30 capture filled with `color`; `paintedHeight` rows from the top are painted and
    /// the rest left clear, like a window captured before its app redrew a new size.
    private func capture(_ color: CGColor, paintedHeight: Int = 30, paintedWidth: Int = 40) -> CGImage {
        let ctx = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color)
        // CGContext's origin is bottom-left: the painted part is the top of the image.
        ctx.fill(CGRect(x: 0, y: 30 - paintedHeight, width: paintedWidth, height: paintedHeight))
        return ctx.makeImage()!
    }

    @Test func edgeColorIsTheWindowsOwnColor() throws {
        let peach = CGColor(srgbRed: 1, green: 0.8, blue: 0.6, alpha: 1)
        let edge = try #require(WindowProxy.edgeColor(of: capture(peach)))
        let c = try #require(edge.components)
        #expect(abs(c[0] - 1) < 0.01 && abs(c[1] - 0.8) < 0.01 && abs(c[2] - 0.6) < 0.01)
    }

    @Test func aClearEdgeHasNoColor() {
        #expect(WindowProxy.edgeColor(of: capture(CGColor(gray: 0.5, alpha: 1), paintedHeight: 10)) == nil)
    }

    @Test func aCaptureIsPaintedOnlyWhenBothFarEdgesAre() {
        let gray = CGColor(gray: 0.5, alpha: 1)
        #expect(WindowProxy.isPainted(capture(gray)))
        #expect(!WindowProxy.isPainted(capture(gray, paintedHeight: 10)))  // bottom not drawn yet
        #expect(!WindowProxy.isPainted(capture(gray, paintedWidth: 20)))   // right side not drawn yet
    }
}
