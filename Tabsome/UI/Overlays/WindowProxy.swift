import AppKit
import QuartzCore
import ScreenCaptureKit
import SwiftUI

/// One-window snapshots for proxies (PLAN.md §5.9, §6.1 S3): only the window being animated,
/// held in memory, released with the proxy. Nil without Screen Recording (the optional
/// permission), or for windows that block capture.
@MainActor
enum WindowCapture {
    /// Screen Recording is allowed. Debug builds can act as if it isn't
    /// (`defaults write com.tabsome.app.dev TabsomeDebugNoCapture -bool YES`) to check the icon cards.
    static var isAllowed: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "TabsomeDebugNoCapture") { return false }
        #endif
        return CGPreflightScreenCaptureAccess()
    }

    static func capture(_ id: CGWindowID) async -> CGImage? {
        guard isAllowed, !Eligibility.secureInputActive,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: Self.configuration(for: window, filter: filter))
    }

    /// A window just resized: tries a few times, 60 ms apart, until the app has painted all of
    /// it. Nil if it never does in time (the proxy then keeps the picture it has).
    static func capturePainted(_ id: CGWindowID, attempts: Int = 4) async -> CGImage? {
        for attempt in 0..<attempts {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(60)) }
            if let image = await capture(id), WindowProxy.isPainted(image) { return image }
        }
        return nil
    }

    private nonisolated static func configuration(for window: SCWindow, filter: SCContentFilter) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return config
    }

    /// Several windows at once, through callbacks only, for Quit's nested run loop (§5.12): one
    /// read of the shareable content, then every capture at the same time. `done` runs on the
    /// main thread with what arrived within `timeout`; windows missing from it get icon cards.
    static func capture(_ ids: [CGWindowID], timeout: TimeInterval, done: @escaping @MainActor ([CGWindowID: CGImage]) -> Void) {
        guard !ids.isEmpty, isAllowed, !Eligibility.secureInputActive else { return done([:]) }
        let batch = CaptureBatch(expected: ids.count, done: done)
        let timer = Timer(timeInterval: timeout, repeats: false) { _ in MainActor.assumeIsolated { batch.finish() } }
        RunLoop.main.add(timer, forMode: .common)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, _ in
            guard let content else { return onMain { batch.finish() } }
            for id in ids {
                guard let window = content.windows.first(where: { $0.windowID == id }) else {
                    onMain { batch.add(id, nil) }
                    continue
                }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration(for: window, filter: filter)) { image, _ in
                    onMain { batch.add(id, image) }
                }
            }
        }
    }

    /// Through the main run loop in common modes, which Quit's nested run loop also serves.
    private nonisolated static func onMain(_ block: @escaping @MainActor @Sendable () -> Void) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { MainActor.assumeIsolated { block() } }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}

/// Collects one batch of captures and reports once: when all are in, or at the timeout.
@MainActor
private final class CaptureBatch {
    private var images: [CGWindowID: CGImage] = [:]
    private var remaining: Int
    private var done: (@MainActor ([CGWindowID: CGImage]) -> Void)?

    init(expected: Int, done: @escaping @MainActor ([CGWindowID: CGImage]) -> Void) {
        remaining = expected
        self.done = done
    }

    func add(_ id: CGWindowID, _ image: CGImage?) {
        if let image { images[id] = image }
        remaining -= 1
        if remaining <= 0 { finish() }
    }

    func finish() {
        let d = done
        done = nil
        d?(images)
    }
}

/// A stand-in for another app's window while it animates: we can't animate other apps' windows,
/// so we animate a picture of it and move the real one underneath (§5.9). The panel covers the
/// screen the animation starts on, ignores the mouse (S7), and sits above normal windows.
///
/// The picture is never scaled. It stays at its real size, anchored at the top-left corner, and
/// any new area is filled with the window's own edge color, the way a window looks during a live
/// resize. A snapshot stretched to a new size reads as zooming (Phase 0, and again in Phase 6).
@MainActor
final class WindowProxy {
    private let panel = OverlayPanel(clickThrough: true)
    /// Fades as one. Holds the shadow and, above it, the clipped picture; both take every move.
    private let root = CALayer()
    private let shadow = CALayer()
    private let content = CALayer()
    private let screenCG: CGRect
    private let scale: CGFloat

    init(image: CGImage?, appPID: pid_t, appName: String, on frame: CGRect) {
        let screen = NSScreen.screens.first { ScreenGeometry.cgRect(fromAppKit: $0.frame).intersects(frame) } ?? NSScreen.screens[0]
        screenCG = ScreenGeometry.cgRect(fromAppKit: screen.frame)
        scale = screen.backingScaleFactor
        panel.level = .floating
        panel.setFrame(screen.frame, display: false)
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        panel.contentView = view
        root.frame = view.bounds
        for layer in [shadow, content] {
            layer.cornerRadius = Metrics.windowCornerRadius
            layer.cornerCurve = .continuous
            root.addSublayer(layer)
        }
        shadow.shadowOpacity = 0.35
        shadow.shadowRadius = 24
        shadow.shadowOffset = CGSize(width: 0, height: -10)
        content.masksToBounds = true
        content.contentsScale = scale
        view.layer?.addSublayer(root)
        if let image {
            show(image)
        } else {
            showIconCard(pid: appPID, name: appName)
        }
    }

    /// A snapshot at its real size, anchored top-left, over its own edge color (kept from
    /// before when this one's edge isn't opaque).
    private func show(_ image: CGImage) {
        content.contents = image
        content.contentsGravity = .topLeft
        content.borderWidth = 0
        if let color = Self.edgeColor(of: image) {
            setFill(color)
        } else if content.backgroundColor == nil {
            setFill(CGColor(gray: 0.5, alpha: 1))
        }
    }

    private func setFill(_ color: CGColor) {
        content.backgroundColor = color
        shadow.backgroundColor = color
    }

    /// The color along the bottom of the window, which is what a growing window shows more of;
    /// nil when it isn't opaque.
    nonisolated static func edgeColor(of image: CGImage) -> CGColor? {
        pixel(of: image, x: image.width / 2, y: image.height - 3)
    }

    /// Whether the app has painted the whole window: a capture taken just after a resize can
    /// come back blank beyond the old size until the app redraws.
    nonisolated static func isPainted(_ image: CGImage) -> Bool {
        pixel(of: image, x: image.width / 2, y: image.height - 3) != nil && pixel(of: image, x: image.width - 3, y: image.height / 2) != nil
    }

    /// One opaque pixel's color (image coordinates, top-left origin), or nil.
    private nonisolated static func pixel(of image: CGImage, x: Int, y: Int) -> CGColor? {
        guard image.width > 4, image.height > 4,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let a = CGFloat(data[3]) / 255
        guard a > 0.5 else { return nil }
        return CGColor(srgbRed: CGFloat(data[0]) / 255 / a, green: CGFloat(data[1]) / 255 / a, blue: CGFloat(data[2]) / 255 / a, alpha: 1)
    }

    /// Without Screen Recording: a window-colored card with the app's icon and name (§5.9). The
    /// card's color fills the frame as it animates, and the icon stays centered at its own size.
    private func showIconCard(pid: pid_t, name: String) {
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        let label = VStack(spacing: 12) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 96, height: 96) }
            Text(name).font(.title2.weight(.semibold))
        }
        .padding(16)
        let renderer = ImageRenderer(content: label)
        renderer.scale = scale
        var background = NSColor.windowBackgroundColor.cgColor
        var border = NSColor.separatorColor.cgColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.cgColor
            border = NSColor.separatorColor.cgColor
        }
        setFill(background)
        content.borderColor = border
        content.borderWidth = 0.5
        content.contents = renderer.cgImage
        content.contentsGravity = .center
    }

    /// A snapshot replaces whatever the proxy showed (the icon card, while it was captured).
    func setImage(_ image: CGImage) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        show(image)
        CATransaction.commit()
    }

    /// Global top-left rect → this panel's layer coordinates (bottom-left origin).
    private func local(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - screenCG.minX, y: screenCG.maxY - r.maxY, width: r.width, height: r.height)
    }

    func show(at frame: CGRect, lifted: Bool = false) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shadow.frame = local(frame)
        content.frame = local(frame)
        root.opacity = lifted ? 0.92 : 1
        CATransaction.commit()
        panel.orderFrontRegardless()
    }

    /// Follows the cursor (tear-out ghost): no animation, the hand drives it (`Motion.interactive`).
    func move(to frame: CGRect) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shadow.frame = local(frame)
        content.frame = local(frame)
        CATransaction.commit()
    }

    /// One spring from where it is to `frame` (`Motion.snappy`'s Core Animation twin).
    func spring(to frame: CGRect) async {
        await withCheckedContinuation { c in spring(to: frame) { c.resume() } }
    }

    /// The same, calling `then` once it has settled. Timed by a run-loop timer in common modes,
    /// so it also runs while Quit waits in a nested run loop (§5.12), where no task may get to run.
    func spring(to frame: CGRect, then: @escaping () -> Void) {
        let target = local(frame)
        let base = Motion.snappySpring()
        // The size doesn't bounce: a frame overshooting its final size reads as zooming past it.
        let sizeSpring = Motion.snappySpring(bounce: 0)
        for layer in [shadow, content] {
            let from = layer.presentation() ?? layer
            let position = base.copy() as! CASpringAnimation
            position.keyPath = "position"
            position.fromValue = NSValue(point: from.position)
            position.toValue = NSValue(point: CGPoint(x: target.midX, y: target.midY))
            position.duration = base.settlingDuration
            let size = sizeSpring.copy() as! CASpringAnimation
            size.keyPath = "bounds.size"
            size.fromValue = NSValue(size: from.bounds.size)
            size.toValue = NSValue(size: target.size)
            size.duration = sizeSpring.settlingDuration
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.position = CGPoint(x: target.midX, y: target.midY)
            layer.bounds.size = target.size
            CATransaction.commit()
            layer.add(position, forKey: "position")
            layer.add(size, forKey: "size")
        }
        Self.after(max(base.settlingDuration, sizeSpring.settlingDuration), then)
    }

    private static func after(_ seconds: TimeInterval, _ block: @escaping () -> Void) {
        // The timer runs on the main run loop, where `block` was made.
        nonisolated(unsafe) let block = block
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in MainActor.assumeIsolated { block() } }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Swap to a snapshot taken at the final size: like the first, anchored and never scaled.
    func crossfade(to image: CGImage) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = Motion.proxyRevealDuration
        content.add(fade, forKey: "contents")
        show(image)
    }

    /// Gone at once (a drop that didn't happen); releases the snapshot (S3).
    func dismiss() {
        panel.orderOut(nil)
        content.contents = nil
    }

    /// Reveal the real window: fade out, then release the panel and the snapshot (S3).
    /// `duration` is longer for Reduce Motion's cross-fade.
    func fadeOut(duration: TimeInterval = Motion.proxyRevealDuration) async {
        await withCheckedContinuation { c in fadeOut(duration: duration) { c.resume() } }
    }

    func fadeOut(duration: TimeInterval = Motion.proxyRevealDuration, then: @escaping () -> Void) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = root.presentation()?.opacity ?? root.opacity
        fade.toValue = 0
        fade.duration = duration
        root.opacity = 0
        root.add(fade, forKey: "fade")
        Self.after(duration) { [self] in
            panel.orderOut(nil)
            content.contents = nil
            then()
        }
    }
}
