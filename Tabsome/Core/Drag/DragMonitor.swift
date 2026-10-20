import AppKit
import CoreGraphics

/// Classifies what the pressed window is doing (PLAN.md §5.1). Pure.
nonisolated enum DragClassifier {
    enum Kind: Equatable { case none, drag, resize }

    /// A move of the origin with the size unchanged is a title-bar drag. Resizing from the top or
    /// left edge moves the origin too, but changes the size.
    static func classify(downFrame: CGRect, current: CGRect, tolerance: CGFloat = 0.5) -> Kind {
        let sizeSame = abs(downFrame.width - current.width) <= tolerance && abs(downFrame.height - current.height) <= tolerance
        let moved = abs(downFrame.minX - current.minX) > tolerance || abs(downFrame.minY - current.minY) > tolerance
        if !sizeSame { return .resize }
        return moved ? .drag : .none
    }
}

/// Mouse button and drag events only, never keystrokes (PLAN.md §6.1 S5). Global monitors see
/// events that go to other apps, which is exactly what's needed: Tabsome's own windows never
/// start a tabbing drag. Points are converted to global top-left coordinates.
@MainActor
final class DragMonitor {
    enum Event {
        case down(CGPoint)
        case dragged(CGPoint)
        case up(CGPoint)
    }

    var onEvent: ((Event, TimeInterval) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            // CGEvent locations are already global, top-left origin.
            guard let point = event.cgEvent?.location else { return }
            let time = event.timestamp
            let kind: Event? = switch event.type {
            case .leftMouseDown: .down(point)
            case .leftMouseDragged: .dragged(point)
            case .leftMouseUp: .up(point)
            default: nil
            }
            guard let kind else { return }
            MainActor.assumeIsolated { self?.onEvent?(kind, time) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
