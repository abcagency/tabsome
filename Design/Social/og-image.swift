// Draws the site's sharing image (Open Graph / Twitter card), 1200×630:
//   swift Design/Social/og-image.swift docs/og.png
// The look follows docs/index.html: the app icon, the name and tagline, and a tabbed window on
// a blue desktop.
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "og.png"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let W = 1200, H = 630

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
// Top-left based rect → AppKit's bottom-left coordinates.
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> NSRect { NSRect(x: x, y: Double(H) - y - h, width: w, height: h) }

// Desktop
NSGradient(colors: [rgb(214, 229, 252), rgb(160, 193, 242), rgb(118, 160, 232)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -70)

// Name, tagline, and icon on the left
let icon = NSImage(contentsOf: root.appendingPathComponent("Design/Icon/Tabsome-appicon-1024.png"))!
icon.draw(in: rect(84, 112, 168, 168))
func text(_ s: String, _ font: NSFont, _ color: NSColor, at x: Double, _ y: Double, width: Double) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: -0.5])
        .draw(with: rect(x, y, width, 400), options: [.usesLineFragmentOrigin])
}
text("Tabsome", .systemFont(ofSize: 92, weight: .bold), rgb(16, 24, 40), at: 80, 304, width: 460)
text("Tabs for any window,\nfrom any app.", .systemFont(ofSize: 40, weight: .medium), rgb(16, 24, 40, 0.72), at: 84, 420, width: 470)

// A tabbed window on the right, bleeding off the edge like a window on a desktop
let win = rect(600, 120, 680, 420)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: rgb(20, 40, 90, 0.35).cgColor)
let shape = NSBezierPath(roundedRect: win, xRadius: 22, yRadius: 22)
NSColor.white.setFill(); shape.fill()
ctx.restoreGState()
NSGraphicsContext.saveGraphicsState()
shape.addClip()
// Tab strip
let strip = rect(600, 120, 680, 64)
rgb(246, 246, 248).setFill(); strip.fill()
rgb(0, 0, 0, 0.08).setFill(); rect(600, 183, 680, 1).fill()
for (i, c) in [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)].enumerated() {
    c.setFill(); NSBezierPath(ovalIn: rect(624 + Double(i) * 26, 143, 18, 18)).fill()
}
func tab(_ x: Double, _ label: String, _ tint: (NSColor, NSColor), active: Bool, badge: String? = nil) {
    let r = rect(x, 132, 164, 40)
    if active {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: rgb(0, 0, 0, 0.14).cgColor)
        NSColor.white.setFill(); NSBezierPath(roundedRect: r, xRadius: 20, yRadius: 20).fill()
        ctx.restoreGState()
    }
    NSGradient(colors: [tint.0, tint.1])!.draw(in: NSBezierPath(roundedRect: rect(x + 16, 142, 20, 20), xRadius: 5, yRadius: 5), angle: -90)
    text(label, .systemFont(ofSize: 19, weight: active ? .semibold : .regular), active ? rgb(29, 29, 31) : rgb(110, 110, 115), at: x + 46, 140, width: 120)
    if let badge {
        rgb(255, 59, 48).setFill(); NSBezierPath(roundedRect: rect(x + 102, 142, 24, 20), xRadius: 10, yRadius: 10).fill()
        text(badge, .systemFont(ofSize: 14, weight: .bold), .white, at: x + 109, 143, width: 20)
    }
}
tab(712, "Safari", (rgb(90, 200, 250), rgb(10, 132, 255)), active: true)
tab(882, "Notes", (rgb(255, 214, 10), rgb(255, 159, 10)), active: false)
tab(1040, "Mail", (rgb(100, 210, 255), rgb(10, 132, 255)), active: false, badge: "3")
// Page content
rgb(0, 0, 0, 0.07).setFill()
for (y, w, h) in [(224.0, 300.0, 24.0), (270, 560, 14), (300, 520, 14), (330, 430, 14), (380, 540, 14), (410, 360, 14)] {
    NSBezierPath(roundedRect: rect(640, y, w, h), xRadius: h / 2, yRadius: h / 2).fill()
}
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(W)×\(H))")
