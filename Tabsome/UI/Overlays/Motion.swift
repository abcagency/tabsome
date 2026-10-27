import QuartzCore
import SwiftUI

/// The only place animation timings live (PLAN.md §5.9). Nothing else picks its own timing.
/// With Reduce Motion on, every token becomes a short cross-fade, which is what macOS does.
@MainActor
enum Motion {
    /// Window snapping into a group, tear-out landing, tab reorder slide.
    static var snappy: Animation { reduced ? crossFade : .snappy }
    /// Strip appearing/disappearing, group dissolving, placement changes.
    static var smooth: Animation { reduced ? crossFade : .smooth }
    /// Drop highlight fade, hover states, close × appearing.
    static var quickFade: Animation { .easeOut(duration: 0.15) }
    /// Anything following the cursor (tab drag, ghost window).
    static var interactive: Animation { reduced ? crossFade : .interactiveSpring }

    /// The Core Animation twin of `snappy`, for overlay panels and window proxies.
    static func snappySpring(bounce: CGFloat = 0.15) -> CASpringAnimation {
        CASpringAnimation(perceptualDuration: 0.3, bounce: bounce)
    }

    /// Proxy hand-off: the snapshot fades out over this once the real window is in place.
    static let proxyRevealDuration: TimeInterval = 0.1
    /// Reduce Motion: a window doesn't travel; its picture fades out over this while the real
    /// window appears in its new place (§5.9), as macOS does.
    static let reducedCrossFadeDuration: TimeInterval = 0.2
    /// The strip gliding with a proxy (Fill and return): AppKit animates window frames on a
    /// curve, not a spring, so this ease-out ends with `snappySpring`'s visible motion.
    static let stripGlideDuration: TimeInterval = 0.32
    static var stripGlideCurve: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1) }

    static var reduced: Bool { SystemAccessibility.shared.reduceMotion }
    private static let crossFade = Animation.easeInOut(duration: 0.2)
}
