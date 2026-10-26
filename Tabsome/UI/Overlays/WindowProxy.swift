import AppKit
import QuartzCore
import ScreenCaptureKit
import SwiftUI

/// One-window snapshots for proxies (PLAN.md §5.9, §6.1 S3): only the window being animated,
/// held in memory, released with the proxy. Nil without Screen Recording (the optional
/// permission), or for windows that block capture.
@MainActor
enum WindowCapture {
    static func capture(_ id: CGWindowID) async -> CGImage? {
        guard CGPreflightScreenCaptureAccess(), !Eligibility.secureInputActive,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// A stand-in for another app's window while it animates: we can't animate other apps' windows,
/// so we animate a picture of it and move the real one underneath (§5.9). The panel covers the
/// screen the animation starts on, ignores the mouse (S7), and sits above normal windows.
@MainActor
final class WindowProxy {
    private let panel = OverlayPanel(clickThrough: true)
    private let layer = CALayer()
    private let screenCG: CGRect

    init(image: CGImage?, appPID: pid_t, appName: String, on frame: CGRect) {
        let screen = NSScreen.screens.first { ScreenGeometry.cgRect(fromAppKit: $0.frame).intersects(frame) } ?? NSScreen.screens[0]
        screenCG = ScreenGeometry.cgRect(fromAppKit: screen.frame)
        panel.level = .floating
        panel.setFrame(screen.frame, display: false)
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        panel.contentView = view
        layer.contentsGravity = .resize
        layer.cornerRadius = Metrics.windowCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: -10)
        view.layer?.addSublayer(layer)
        layer.contents = image ?? Self.iconCard(pid: appPID, name: appName, size: frame.size)
    }

    /// Without Screen Recording: a glass card with the app's icon and name (§5.9).
    private static func iconCard(pid: pid_t, name: String, size: CGSize) -> CGImage? {
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        let card = ZStack {
            RoundedRectangle(cornerRadius: Metrics.windowCornerRadius, style: .continuous).fill(.regularMaterial)
            VStack(spacing: 12) {
                if let icon { Image(nsImage: icon).resizable().frame(width: 96, height: 96) }
                Text(name).font(.title2.weight(.semibold))
            }
        }
        .frame(width: max(size.width, 200), height: max(size.height, 160))
        let renderer = ImageRenderer(content: card)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.cgImage
    }

    func setImage(_ image: CGImage) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }

    /// Global top-left rect → this panel's layer coordinates (bottom-left origin).
    private func local(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - screenCG.minX, y: screenCG.maxY - r.maxY, width: r.width, height: r.height)
    }

    func show(at frame: CGRect, lifted: Bool = false) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.frame = local(frame)
        layer.opacity = lifted ? 0.92 : 1
        CATransaction.commit()
        panel.orderFrontRegardless()
    }

    /// Follows the cursor (tear-out ghost): no animation, the hand drives it (`Motion.interactive`).
    func move(to frame: CGRect) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.frame = local(frame)
        CATransaction.commit()
    }

    /// One spring from where it is to `frame` (`Motion.snappy`'s Core Animation twin).
    func spring(to frame: CGRect) async {
        let target = local(frame)
        let base = Motion.snappySpring()
        let from = layer.presentation() ?? layer
        let position = base.copy() as! CASpringAnimation
        position.keyPath = "position"
        position.fromValue = NSValue(point: from.position)
        position.toValue = NSValue(point: CGPoint(x: target.midX, y: target.midY))
        let size = base.copy() as! CASpringAnimation
        size.keyPath = "bounds.size"
        size.fromValue = NSValue(size: from.bounds.size)
        size.toValue = NSValue(size: target.size)
        position.duration = base.settlingDuration
        size.duration = base.settlingDuration
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.position = CGPoint(x: target.midX, y: target.midY)
        layer.bounds.size = target.size
        CATransaction.commit()
        layer.add(position, forKey: "position")
        layer.add(size, forKey: "size")
        try? await Task.sleep(for: .seconds(base.settlingDuration))
    }

    /// Swap to a snapshot taken at the final size, so nothing is left looking stretched.
    func crossfade(to image: CGImage) {
        let fade = CABasicAnimation(keyPath: "contents")
        fade.fromValue = layer.contents
        fade.toValue = image
        fade.duration = Motion.proxyRevealDuration
        layer.contents = image
        layer.add(fade, forKey: "contents")
    }

    /// Gone at once (a drop that didn't happen); releases the snapshot (S3).
    func dismiss() {
        panel.orderOut(nil)
        layer.contents = nil
    }

    /// Reveal the real window: fade out, then release the panel and the snapshot (S3).
    func fadeOut() async {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = 0
        fade.duration = Motion.proxyRevealDuration
        layer.opacity = 0
        layer.add(fade, forKey: "fade")
        try? await Task.sleep(for: .seconds(Motion.proxyRevealDuration))
        panel.orderOut(nil)
        layer.contents = nil
    }
}
