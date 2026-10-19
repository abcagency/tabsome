// Spike 6: proxy animation (plan §5.9). Snapshot a window with ScreenCaptureKit, spring the
// snapshot to a new frame, move the real window underneath with AX, then swap with no pop.
// Needs Accessibility + Screen Recording.
//
// Two choreographies are measured per app:
//   cover: the destination is covered by another window T (the snap-in case). Activate T,
//          move the real window D behind T, spring the proxy, raise D, fade the proxy.
//   park:  nothing covers the destination (flyout presets). Park D in the screen corner,
//          spring the proxy, then move D to the destination, wait for it to land, fade.
//
//   proxy [bid ...]   default: Safari, Terminal, VS Code. Cover window = Finder.

import AppKit
import QuartzCore
import ScreenCaptureKit

@MainActor
enum S6 {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        guard CGPreflightScreenCaptureAccess() else {
            log("SCREEN RECORDING NOT GRANTED. System Settings › Privacy & Security › Screen & System Audio Recording → enable TabsomeSpikes, then re-run.")
            _ = CGRequestScreenCaptureAccess()
            return
        }
        keepAlive = true
        if args.first == "compare" {
            Task { @MainActor in
                let runs: [(String, String)] = [("stretch", "1 of 4: STRETCH (current): snapshot scaled to the new size"),
                                                ("crossfade", "2 of 4: CROSS-FADE to a snapshot taken at the final size"),
                                                ("stretch", "3 of 4: STRETCH again"),
                                                ("crossfade", "4 of 4: CROSS-FADE again")]
                for (mode, label) in runs {
                    banner(label)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await animate(bid: "com.apple.Safari", mode: mode == "stretch" ? "cover" : "crossfade")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
                bannerPanel?.orderOut(nil)
                finish()
            }
            return
        }
        let bids = args.isEmpty ? ["com.apple.Safari", "com.apple.Terminal", "com.microsoft.VSCode"] : Array(args)
        Task { @MainActor in
            for bid in bids {
                for mode in ["cover", "park"] { await animate(bid: bid, mode: mode) }
            }
            finish()
        }
    }

    static func waitUntil(_ timeout: Double, _ cond: () -> Bool) async -> Double? {
        let s = now()
        while now() - s < timeout {
            if cond() { return now() - s }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return cond() ? now() - s : nil
    }

    /// Landed = within 8 pt of the target and unchanged across two consecutive polls 4 ms apart
    /// (grid-snapping apps like Terminal never match exactly).
    static func landed(_ id: CGWindowID, _ target: CGRect) async -> Double? {
        let s = now()
        var last: CGRect?
        while now() - s < 1.5 {
            let b = cgWindows(onScreenOnly: false).first { $0.id == id }?.bounds
            if let b, close(b, target, 8), b == last { return now() - s }
            last = b
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
        return nil
    }

    static func close(_ a: CGRect, _ b: CGRect, _ tol: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
    }

    static func animate(bid: String, mode: String) async {
        guard let app = runningApp(bid), let d = axStandardWindows(pid: app.processIdentifier).first, let dID = windowID(d),
              let finder = runningApp("com.apple.finder"), let t = axStandardWindows(pid: finder.processIdentifier).first, let tID = windowID(t)
        else { log("\(bid): need a window here and a Finder window"); return }
        let name = app.localizedName ?? bid
        let dOrig = axFrame(d)!, tOrig = axFrame(t)!
        let A = CGRect(x: 160, y: 180, width: 720, height: 460)
        let B = CGRect(x: 640, y: 300, width: 820, height: 520)

        // Setup: T at B (cover mode only), D at A on top.
        let covered = mode == "cover" || mode == "crossfade"
        if covered { axSetFrame(t, B) } else { axSetFrame(t, CGRect(x: 40, y: 700, width: 500, height: 300)) }
        axSetFrame(d, A)
        try? await Task.sleep(nanoseconds: 300_000_000)
        activate(window: d, pid: app.processIdentifier, method: .nsRunningApp)
        _ = await waitUntil(1.5) { frontmostPID() == app.processIdentifier }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let aReal = axFrame(d)!

        // 1. Snapshot.
        let t0 = now()
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let scw = content.windows.first(where: { $0.windowID == dID }) else { log("\(name): SCWindow not found"); return }
        let tContent = now() - t0
        let filter = SCContentFilter(desktopIndependentWindow: scw)
        let cfg = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        cfg.width = Int(aReal.width * scale); cfg.height = Int(aReal.height * scale)
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        let t1 = now()
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { log("\(name): capture failed"); return }
        let tCapture = now() - t1

        // 2. Proxy panel over the union of both frames.
        let union = aReal.union(B).insetBy(dx: -40, dy: -40)
        let panel = NSPanel(contentRect: nsRect(fromCG: union), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        let view = NSView(frame: NSRect(origin: .zero, size: union.size))
        view.wantsLayer = true
        panel.contentView = view
        let layer = CALayer()
        layer.contents = img
        layer.contentsGravity = .resize
        layer.shadowOpacity = 0.35; layer.shadowRadius = 24; layer.shadowOffset = CGSize(width: 0, height: -10)
        func local(_ r: CGRect) -> CGRect { // CG global (top-left) → layer coords (bottom-left)
            CGRect(x: r.minX - union.minX, y: union.maxY - r.maxY, width: r.width, height: r.height)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.frame = local(aReal)
        view.layer!.addSublayer(layer)
        CATransaction.commit()
        panel.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 30_000_000) // one or two frames for the proxy to be on screen

        // 3. Hide/move the real window underneath.
        let t2 = now()
        var landAt: Double?
        var img2: CGImage?
        if covered {
            activate(window: t, pid: finder.processIdentifier, method: .nsRunningApp) // D drops behind T
            axSetFrame(d, B)
            landAt = await landed(dID, B)
            if mode == "crossfade", let content2 = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
               let scw2 = content2.windows.first(where: { $0.windowID == dID }) {
                // The real window is behind T at its final size; ScreenCaptureKit still captures it.
                let cfg2 = SCStreamConfiguration()
                let real = cgWindows(onScreenOnly: false).first { $0.id == dID }?.bounds ?? B
                cfg2.width = Int(real.width * scale); cfg2.height = Int(real.height * scale)
                cfg2.showsCursor = false; cfg2.ignoreShadowsSingleWindow = true
                img2 = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: scw2), configuration: cfg2)
                log("  crossfade: final-size capture \(img2 != nil ? "ok" : "FAILED") while covered")
            }
        } else {
            let screen = NSScreen.screens[0].frame
            axSetPosition(d, CGPoint(x: screen.maxX - 1, y: screen.maxY - 1)) // corner park
        }
        let tHide = now() - t2

        // 4. Spring.
        let spring = CASpringAnimation(perceptualDuration: 0.3, bounce: 0.15)
        let endR = local(B)
        let pos = spring.copy() as! CASpringAnimation
        pos.keyPath = "position"; pos.fromValue = NSValue(point: CGPoint(x: layer.frame.midX, y: layer.frame.midY)); pos.toValue = NSValue(point: CGPoint(x: endR.midX, y: endR.midY))
        let bnd = spring.copy() as! CASpringAnimation
        bnd.keyPath = "bounds.size"; bnd.fromValue = NSValue(size: layer.bounds.size); bnd.toValue = NSValue(size: endR.size)
        pos.duration = spring.settlingDuration; bnd.duration = spring.settlingDuration
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.position = CGPoint(x: endR.midX, y: endR.midY); layer.bounds.size = endR.size
        CATransaction.commit()
        layer.add(pos, forKey: "p"); layer.add(bnd, forKey: "b")
        if let img2 {
            let fade = CABasicAnimation(keyPath: "contents")
            fade.fromValue = img; fade.toValue = img2
            fade.duration = spring.settlingDuration * 0.5
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.contents = img2
            layer.add(fade, forKey: "c")
        }
        let animStart = now()
        try? await Task.sleep(nanoseconds: UInt64(spring.settlingDuration * 1e9))

        // 5. Reveal.
        let t3 = now()
        var raiseLat: Double?
        if mode == "park" {
            axSetFrame(d, B)
            landAt = await landed(dID, B)
        }
        activate(window: d, pid: app.processIdentifier, method: .nsRunningApp)
        raiseLat = await waitUntil(1.0) { cgWindows().filter { $0.layer == 0 && ($0.id == dID || $0.id == tID) }.first?.id == dID }
        let final = cgWindows(onScreenOnly: false).first { $0.id == dID }?.bounds ?? .zero
        try? await Task.sleep(nanoseconds: 16_000_000)
        await NSAnimationContext.runAnimationGroup { c in c.duration = 0.1; panel.animator().alphaValue = 0 }
        panel.orderOut(nil)
        let mismatch = String(format: "Δx %.0f Δy %.0f Δw %.0f Δh %.0f", final.minX - B.minX, final.minY - B.minY, final.width - B.width, final.height - B.height)

        log("\(name) [\(mode)]: SCShareableContent \(ms(tContent)), capture \(ms(tCapture)) (\(img.width)x\(img.height)px), hide step \(ms(tHide)), AX land \(landAt.map(ms) ?? "NEVER/inexact") \(mode == "park" ? "(after spring, from \(ms(now() - t3)) reveal start)" : ""), spring settle \(ms(spring.settlingDuration)), raise \(raiseLat.map(ms) ?? "?"), final vs target \(mismatch) — total \(ms(now() - animStart + (animStart - t0)))")

        axSetFrame(d, dOrig); axSetFrame(t, tOrig)
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
}
