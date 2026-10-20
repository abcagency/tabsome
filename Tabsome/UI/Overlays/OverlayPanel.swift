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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
