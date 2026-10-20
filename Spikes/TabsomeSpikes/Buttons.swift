// Tooling: sample the real window buttons' colors (red/yellow/green, or graphite) from a
// window of `bid`, focused and unfocused, so Tabsome's drawn buttons can match them.
//   buttons [bid]   default Finder

import AppKit
import ScreenCaptureKit

@MainActor
enum Buttons {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        keepAlive = true
        let bid = args.first ?? "com.apple.finder"
        Task { @MainActor in
            if bid == "own" { await sampleOwn() } else { await sample(bid) }
            finish()
        }
    }

    static func sample(_ bid: String) async {
        guard let app = runningApp(bid), let w = axStandardWindows(pid: app.processIdentifier).first, let wid = windowID(w),
              let other = NSWorkspace.shared.runningApplications.first(where: { $0.activationPolicy == .regular && $0.processIdentifier != app.processIdentifier && $0.bundleIdentifier != "com.tabsome.app" })
        else { log("need a window in \(bid)"); return }
        log("accent AppleAccentColor=\(UserDefaults.standard.object(forKey: "AppleAccentColor") ?? "nil (multicolor)") appearance=\(NSApp.effectiveAppearance.name.rawValue)")
        let buttons = [kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute].compactMap { axElement(w, $0).flatMap(axFrame) }
        guard buttons.count == 3, let wf = axFrame(w) else { log("no buttons"); return }
        for (label, focus) in [("focused", true), ("unfocused", false)] {
            if focus { activate(window: w, pid: app.processIdentifier, method: .nsRunningApp) } else { other.activate() }
            try? await Task.sleep(for: .milliseconds(700))
            guard let image = await capture(wid) else { log("capture failed"); return }
            let scale = CGFloat(image.width) / wf.width
            var parts: [String] = []
            for (name, b) in zip(["close", "minimize", "zoom"], buttons) {
                // Centre of the button, relative to the window.
                let p = CGPoint(x: (b.midX - wf.minX) * scale, y: (b.midY - wf.minY) * scale)
                parts.append("\(name) \(hex(image, at: p))")
                // Also a point near the rim (the darker border).
                let rim = CGPoint(x: (b.midX - wf.minX) * scale, y: (b.minY + 1.6 - wf.minY) * scale)
                parts.append("rim \(hex(image, at: rim))")
            }
            log("\(label): " + parts.joined(separator: "  "))
        }
    }

    /// Our own titled windows forced to Light and Dark, focused (key) and not.
    static func sampleOwn() async {
        for (label, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            // A non-activating panel can become key without its app being active.
            let keyable = ProcessInfo.processInfo.environment["UNFOCUSED"] == nil
            let w: NSWindow = keyable
                ? NSPanel(contentRect: NSRect(x: 300, y: 300, width: 420, height: 160), styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
                : NSWindow(contentRect: NSRect(x: 300, y: 300, width: 420, height: 160), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            (w as? NSPanel)?.becomesKeyOnlyIfNeeded = false
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: name)
            w.title = "Buttons \(label)"
            if keyable {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
                w.makeKeyAndOrderFront(nil)
            } else {
                w.orderFrontRegardless()
            }
            try? await Task.sleep(for: .milliseconds(800))
            let buttons: [NSButton] = [.closeButton, .miniaturizeButton, .zoomButton].compactMap { w.standardWindowButton($0) }
            for state in ["key=\(w.isKeyWindow) active=\(NSApp.isActive)", "after deactivating"] {
                if state == "after deactivating" {
                    runningApp("com.apple.finder")?.activate()
                    try? await Task.sleep(for: .milliseconds(800))
                }
                guard let image = await capture(CGWindowID(w.windowNumber)) else { log("capture failed"); continue }
                Shot.save(image, "buttons-\(label)")
                let scale = CGFloat(image.width) / w.frame.width
                let parts = buttons.map { b -> String in
                    let r = b.convert(b.bounds, to: nil) // window coords, bottom-left
                    let p = CGPoint(x: r.midX * scale, y: (w.frame.height - r.midY) * scale)
                    // The rim: half a point inside the visible 14 pt circle's edge.
                    let rim = CGPoint(x: r.midX * scale, y: (w.frame.height - r.midY - 6.5) * scale)
                    return "\(hex(image, at: p)) rim \(hex(image, at: rim))"
                }
                log("\(label) [\(state)]: close \(parts[0])  minimize \(parts[1])  zoom \(parts[2])")
            }
            w.orderOut(nil)
        }
    }

    static func capture(_ wid: CGWindowID) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let scw = content.windows.first(where: { $0.windowID == wid }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scw)
        let cfg = SCStreamConfiguration()
        let s = CGFloat(filter.pointPixelScale)
        cfg.width = Int(scw.frame.width * s); cfg.height = Int(scw.frame.height * s)
        cfg.ignoreShadowsSingleWindow = true
        cfg.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    static func hex(_ img: CGImage, at p: CGPoint) -> String {
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "?" }
        ctx.translateBy(x: -p.x, y: -(CGFloat(img.height) - p.y))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let d = ctx.data!.bindMemory(to: UInt8.self, capacity: 4)
        return String(format: "#%02X%02X%02X", d[0], d[1], d[2])
    }
}
