import AppKit

/// The shared base for everything Tabsome draws over the desktop (PLAN.md §4): borderless,
/// non-activating, no shadow, and no AppKit window animation (Phase 0: the default fades
/// `orderOut` for ~270 ms; overlays animate their own content with `Motion`).
final class OverlayPanel: NSPanel {
    init(clickThrough: Bool) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = false
        level = .normal
        hidesOnDeactivate = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
        isReleasedWhenClosed = false
        // S7: overlays that sit over another app's content never take its clicks.
        ignoresMouseEvents = clickThrough
        collectionBehavior = [.managed, .fullScreenNone, .ignoresCycle]
    }

    /// Puts `view` inside a plain container that fills the panel. The panel's frame always comes
    /// from Tabsome (a group, a target window), never from SwiftUI: a hosting view that is the
    /// content view resizes its window to the view's ideal size (zero for views that fill what
    /// they're given).
    func setHostedContent(_ view: NSView) {
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizesSubviews = true
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
