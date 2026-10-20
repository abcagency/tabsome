// Tooling (not a spike): capture windows of an app, or the menu bar, to PNGs so the session can
// check UI without the user taking screenshots.
//   shot <owner name> [more names...]    every on-screen window of those apps → out/shots/
//   shot menubar                         the right half of the main display's menu bar

import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
enum Shot {
    static func run(_ args: ArraySlice<String>) {
        keepAlive = true
        Task { @MainActor in
            await capture(Array(args))
            finish()
        }
    }

    static func save(_ image: CGImage, _ name: String) {
        let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name + ".png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        log("saved \(url.path) (\(image.width)x\(image.height))")
    }

    static func capture(_ names: [String]) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { log("no shareable content"); return }
        if names.first == "menubar", let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            let r = CGRect(x: CGFloat(display.width) * 0.5, y: 0, width: CGFloat(display.width) * 0.5, height: 34)
            cfg.sourceRect = r
            cfg.width = Int(r.width * scale); cfg.height = Int(r.height * scale)
            if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { save(img, "menubar") }
            return
        }
        var n = 0
        for w in content.windows where w.isOnScreen && names.contains(where: { $0 == w.owningApplication?.applicationName }) && w.frame.width > 40 {
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let cfg = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            cfg.width = Int(w.frame.width * scale); cfg.height = Int(w.frame.height * scale)
            cfg.showsCursor = false
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { continue }
            n += 1
            save(img, "\(w.owningApplication?.applicationName ?? "app")-\(n)")
        }
        if n == 0 { log("no on-screen windows for \(names)") }
    }
}
