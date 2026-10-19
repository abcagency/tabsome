// Spike 8: measure the current macOS look (plan §5.15): window-button size/spacing/inset,
// title bar / toolbar / tab bar heights, corner radii, tab sizes.
//   A. our own NSWindows in several styles (no permission needed)
//   B. real Safari / Finder / Terminal windows through AX (spike-only: reads below window level)
//   C. corner radius from a ScreenCaptureKit capture of those windows (needs Screen Recording)

import AppKit
import ScreenCaptureKit

@MainActor
enum S8 {
    static func run(_ args: ArraySlice<String>) {
        keepAlive = true
        partA()
        if AXIsProcessTrusted() { partB() } else { log("B skipped: no Accessibility") }
        Task { @MainActor in
            if CGPreflightScreenCaptureAccess() { await partC() } else { log("C skipped: no Screen Recording") }
            finish()
        }
    }

    // MARK: A

    static func buttons(_ w: NSWindow) -> String {
        let types: [(String, NSWindow.ButtonType)] = [("close", .closeButton), ("min", .miniaturizeButton), ("zoom", .zoomButton)]
        var frames: [CGRect] = []
        for (_, t) in types {
            guard let b = w.standardWindowButton(t) else { continue }
            let r = b.convert(b.bounds, to: nil) // window coords, bottom-left origin
            frames.append(r)
        }
        guard frames.count == 3 else { return "buttons n/a" }
        let H = w.frame.height
        let c = frames[0]
        let fromTop = H - c.maxY
        return String(format: "button %.1fx%.1f, close.minX %.1f, gap %.1f/%.1f, pitch %.1f, top inset %.1f, centerY-from-top %.1f",
                      c.width, c.height, c.minX, frames[1].minX - frames[0].maxX, frames[2].minX - frames[1].maxX,
                      frames[1].minX - frames[0].minX, fromTop, fromTop + c.height / 2)
    }

    static func cornerRadius(_ w: NSWindow) -> String {
        for key in ["_cornerRadius", "cornerRadius", "_effectiveCornerRadius"] where w.responds(to: Selector((key))) {
            if let n = w.value(forKey: key) as? NSNumber { return "\(key)=\(n)" }
        }
        return "radius n/a"
    }

    static func findSubview(_ v: NSView, _ match: (NSView) -> Bool) -> NSView? {
        if match(v) { return v }
        for s in v.subviews { if let f = findSubview(s, match) { return f } }
        return nil
    }

    static func partA() {
        log("A. Own NSWindow measurements (points)")
        let configs: [(String, (NSWindow) -> Void)] = [
            ("titled, no toolbar", { _ in }),
            ("toolbar .unified", { w in w.toolbar = NSToolbar(); w.toolbarStyle = .unified }),
            ("toolbar .unifiedCompact", { w in w.toolbar = NSToolbar(); w.toolbarStyle = .unifiedCompact }),
            ("toolbar .expanded", { w in w.toolbar = NSToolbar(); w.toolbarStyle = .expanded }),
            ("fullSizeContent + transparent titlebar", { w in w.styleMask.insert(.fullSizeContentView); w.titlebarAppearsTransparent = true }),
        ]
        for (label, apply) in configs {
            let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 400),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = "Metrics"
            apply(w)
            w.orderFront(nil)
            spin(0.2)
            let titlebar = w.frame.height - w.contentLayoutRect.height
            log(String(format: "  %@: titlebar+toolbar %.1f; %@; %@", label, titlebar, buttons(w), cornerRadius(w)))
            w.orderOut(nil)
        }
        // Native tab bar: two tabbed windows.
        let w1 = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let w2 = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w1.isReleasedWhenClosed = false; w2.isReleasedWhenClosed = false
        w1.title = "Tab One"; w2.title = "Tab Two"
        w1.tabbingMode = .preferred; w2.tabbingMode = .preferred
        w1.orderFront(nil); w1.addTabbedWindow(w2, ordered: .above); w2.orderFront(nil)
        spin(0.4)
        let titlebar = w2.frame.height - w2.contentLayoutRect.height
        var tabInfo = "tab bar view not found"
        if let theme = w2.contentView?.superview,
           let bar = findSubview(theme, { String(describing: type(of: $0)).contains("TabBar") }) {
            tabInfo = String(format: "%@ height %.1f width %.1f", String(describing: type(of: bar)), bar.frame.height, bar.frame.width)
            let tabs = bar.subviews.flatMap { [$0] + $0.subviews }.filter { String(describing: type(of: $0)).contains("TabButton") || String(describing: type(of: $0)).contains("Tab") }
            for t in tabs.prefix(6) { tabInfo += String(format: "; %@ %.1fx%.1f", String(describing: type(of: t)), t.frame.width, t.frame.height) }
        }
        log(String(format: "  native window tabs (2 tabs): titlebar+tabbar %.1f; %@; %@", titlebar, buttons(w2), tabInfo))
        w1.orderOut(nil); w2.orderOut(nil)
    }

    // MARK: B

    static func descendants(_ el: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth > 0 else { return [] }
        let kids = axElements(el, kAXChildrenAttribute)
        return kids + kids.flatMap { descendants($0, depth: depth - 1) }
    }

    static func partB() {
        log("B. Real windows via AX (points, relative to the window's top-left)")
        for bid in ["com.apple.Safari", "com.apple.finder", "com.apple.Terminal", "com.apple.Notes"] {
            guard let app = runningApp(bid), let w = axStandardWindows(pid: app.processIdentifier).first, let wf = axFrame(w) else { log("  \(bid): no window"); continue }
            let name = app.localizedName ?? bid
            var line = String(format: "  %@: window %.0fx%.0f", name, wf.width, wf.height)
            let btns = [kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute].compactMap { axElement(w, $0).flatMap(axFrame) }
            if btns.count == 3 {
                let c = btns[0]
                line += String(format: "; button %.1fx%.1f, close inset x %.1f, centerY %.1f, gaps %.1f/%.1f, pitch %.1f",
                               c.width, c.height, c.minX - wf.minX, c.midY - wf.minY, btns[1].minX - btns[0].maxX, btns[2].minX - btns[1].maxX, btns[1].minX - btns[0].minX)
            }
            let all = descendants(w, depth: 7)
            if let tb = all.first(where: { axString($0, kAXRoleAttribute) == kAXToolbarRole }), let tf = axFrame(tb) {
                line += String(format: "; toolbar y %.1f h %.1f", tf.minY - wf.minY, tf.height)
            }
            // Content area: the first big scroll area / web area / text area.
            if let content = all.first(where: { ["AXWebArea", kAXScrollAreaRole, kAXSplitGroupRole].contains(axString($0, kAXRoleAttribute) ?? "") }),
               let cf = axFrame(content) {
                line += String(format: "; content starts at y %.1f (%@)", cf.minY - wf.minY, axString(content, kAXRoleAttribute) ?? "")
            }
            log(line)
            if let tg = all.first(where: { axString($0, kAXRoleAttribute) == kAXTabGroupRole }), let tgf = axFrame(tg) {
                let tabs = axElements(tg, kAXChildrenAttribute).compactMap { el -> CGRect? in
                    let r = axString(el, kAXRoleAttribute) ?? ""
                    return (r == kAXRadioButtonRole || r == "AXTab") ? axFrame(el) : nil
                }
                var tl = String(format: "    tab group y %.1f h %.1f, %d tabs", tgf.minY - wf.minY, tgf.height, tabs.count)
                for (i, t) in tabs.prefix(6).enumerated() {
                    tl += String(format: "; tab%d x %.1f w %.1f h %.1f", i, t.minX - wf.minX, t.width, t.height)
                    if i > 0 { tl += String(format: " gap %.1f", t.minX - tabs[i - 1].maxX) }
                }
                log(tl)
            }
        }
    }

    // MARK: C

    static func partC() async {
        log("C. Corner radius from window captures (alpha scan, points)")
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { log("  SCShareableContent failed"); return }
        for bid in ["com.apple.Safari", "com.apple.finder", "com.apple.Terminal", "com.apple.Notes"] {
            guard let app = runningApp(bid), let w = axStandardWindows(pid: app.processIdentifier).first, let wid = windowID(w),
                  let scw = content.windows.first(where: { $0.windowID == wid }) else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: scw)
            let cfg = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            cfg.width = Int(scw.frame.width * scale); cfg.height = Int(scw.frame.height * scale)
            cfg.ignoreShadowsSingleWindow = true
            cfg.showsCursor = false
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { continue }
            log("  \(app.localizedName ?? bid): top-left \(radius(img, corner: 0, scale: scale)), bottom-left \(radius(img, corner: 1, scale: scale)) (image \(img.width)x\(img.height), scale \(scale))")
        }
    }

    /// Estimate the corner radius from where the 45° diagonal first becomes opaque:
    /// for a circular corner of radius r the diagonal hits the arc at k = r(1 − 1/√2).
    static func radius(_ img: CGImage, corner: Int, scale: CGFloat) -> String {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "?" }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return "?" }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // CGContext memory row 0 = top of image.
        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }
        var k = 0
        while k < min(w, h) / 2 {
            let y = corner == 0 ? k : h - 1 - k
            if alpha(k, y) > 127 { break }
            k += 1
        }
        // Transparent run along the outer edge row, a second estimate (≈ r).
        let edgeY = corner == 0 ? 0 : h - 1
        var run = 0
        while run < w / 2 && alpha(run, edgeY) <= 127 { run += 1 }
        let r = CGFloat(k) / (1 - 1 / 2.0.squareRoot()) / scale
        return String(format: "≈%.1f pt (diagonal), edge run %.1f pt", r, CGFloat(run) / scale)
    }
}
