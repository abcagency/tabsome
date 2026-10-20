// Tooling for Phase 2+ verification: synthesizes "drag window A onto window B's middle and
// pause" against the real Tabsome app, capturing the screen while the cursor is held still.
//   tabdrag [draggedBID targetBID] [--hold 1.2] [--release-in-zone]
// Shots: out/shots/tabdrag-armed.png (holding in the middle), tabdrag-away.png (moved off).

import AppKit
import ScreenCaptureKit

@MainActor
enum TabDrag {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        keepAlive = true
        let bids = args.filter { $0.contains(".") && $0.first?.isLetter == true }
        let draggedBID = bids.first ?? "com.apple.finder", targetBID = bids.dropFirst().first ?? "com.apple.Safari"
        let hold = args.firstIndex(of: "--hold").flatMap { Double(args[args.index(after: $0)]) } ?? 1.2
        let releaseInZone = args.contains("--release-in-zone")
        Task { @MainActor in
            await go(draggedBID, targetBID, hold: hold, releaseInZone: releaseInZone)
            finish()
        }
    }

    static func go(_ draggedBID: String, _ targetBID: String, hold: Double, releaseInZone: Bool) async {
        guard let dApp = runningApp(draggedBID), let tApp = runningApp(targetBID),
              let d = axStandardWindows(pid: dApp.processIdentifier).first, let t = axStandardWindows(pid: tApp.processIdentifier).first
        else { log("need a window in \(draggedBID) and \(targetBID)"); return }
        let dOrig = axFrame(d)!, tOrig = axFrame(t)!
        let targetFrame = CGRect(x: 160, y: 200, width: 1000, height: 640)
        axSetFrame(t, targetFrame)
        axSetFrame(d, CGRect(x: 1220, y: 240, width: 620, height: 420))
        activate(window: t, pid: tApp.processIdentifier, method: .nsRunningApp)
        try? await Task.sleep(for: .milliseconds(400))
        activate(window: d, pid: dApp.processIdentifier, method: .nsRunningApp)
        try? await Task.sleep(for: .milliseconds(500))
        let df = axFrame(d)!
        let grab = CGPoint(x: df.midX + 80, y: df.minY + 12)
        let middle = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let away = CGPoint(x: targetFrame.minX + 40, y: targetFrame.maxY - 30) // over the target, outside its middle

        let t0 = ProcessInfo.processInfo.systemUptime
        Task.detached {
            postMouse(.mouseMoved, grab); usleep(80_000)
            postMouse(.leftMouseDown, grab); usleep(150_000)
            func drag(_ a: CGPoint, _ b: CGPoint, _ steps: Int) {
                for i in 1...steps {
                    let f = CGFloat(i) / CGFloat(steps)
                    postMouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)); usleep(12_000)
                }
            }
            drag(grab, middle, 50)
            usleep(useconds_t(hold * 1_000_000))         // the pause
            if releaseInZone { postMouse(.leftMouseUp, middle); return }
            drag(middle, away, 25)
            usleep(700_000)
            postMouse(.leftMouseUp, away)
        }
        // Drag takes 0.08 + 0.15 + 50×0.012 ≈ 0.83 s; capture late in the hold, then after moving away.
        try? await Task.sleep(for: .seconds(0.83 + hold - 0.15))
        await shoot(region: targetFrame.insetBy(dx: -30, dy: -60), name: "tabdrag-armed")
        log(String(format: "armed shot at %.2f s", ProcessInfo.processInfo.systemUptime - t0))
        if !releaseInZone {
            try? await Task.sleep(for: .seconds(0.15 + 0.3 + 0.45))
            await shoot(region: targetFrame.insetBy(dx: -30, dy: -60), name: "tabdrag-away")
        }
        try? await Task.sleep(for: .seconds(1.0))
        axSetFrame(d, dOrig); axSetFrame(t, tOrig)
    }

    static func shoot(region: CGRect, name: String) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: region.midX, y: region.midY)) }) else { return }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let local = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        cfg.sourceRect = local
        cfg.width = Int(local.width * scale / 2); cfg.height = Int(local.height * scale / 2)
        cfg.showsCursor = true
        if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { Shot.save(img, name) }
    }
}
