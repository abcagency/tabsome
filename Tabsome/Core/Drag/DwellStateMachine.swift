import CoreGraphics
import Foundation

/// "Pause for a moment" (PLAN.md §5.3). Pure: it takes the cursor, the time, and the target
/// whose middle zone is under the cursor, and returns effects for the caller to perform.
///
/// The cursor has to stay within `jitter` points for `dwell` seconds over the same target. The
/// cursor doesn't move while the user pauses, so no events arrive: the machine asks for a
/// one-shot `tick` at the moment the dwell would complete.
nonisolated struct DwellStateMachine: Equatable {
    struct Config: Equatable {
        /// 450 ms by default; Settings allows 200–1000 ms (Phase 6).
        var dwell: TimeInterval = 0.45
        /// Movement under this many points doesn't restart the pause.
        var jitter: CGFloat = 6
    }

    enum State: Equatable {
        case idle
        case hovering(target: CGWindowID, anchor: CGPoint, since: TimeInterval)
        case armed(target: CGWindowID)
        // Phase 4 adds `armedOnStrip(target:insertIndex:)`: no dwell over a tab strip (§5.2).
    }

    enum Effect: Equatable {
        case showHighlight(target: CGWindowID)
        case hideHighlight
        /// Call `tick(time:)` at this time (replacing any earlier request).
        case scheduleTick(at: TimeInterval)
        /// Mouse up while armed: tab the dragged window into the target (Phase 3).
        case drop(target: CGWindowID)
    }

    let config: Config
    private(set) var state = State.idle

    init(config: Config = Config()) {
        self.config = config
    }

    /// The cursor moved (or the target under it was re-resolved).
    /// - Parameter target: the eligible window whose middle zone contains the cursor, if any.
    mutating func update(cursor: CGPoint, time: TimeInterval, target: CGWindowID?) -> [Effect] {
        switch state {
        case .idle:
            guard let target else { return [] }
            return startHovering(target, cursor, time)

        case .hovering(let current, let anchor, let since):
            guard let target else {
                state = .idle
                return []
            }
            if target != current || distance(cursor, anchor) >= config.jitter {
                return startHovering(target, cursor, time)
            }
            return time - since >= config.dwell ? arm(target) : []

        case .armed(let current):
            guard let target else {
                state = .idle
                return [.hideHighlight]
            }
            if target == current { return [] }
            return [.hideHighlight] + startHovering(target, cursor, time)
        }
    }

    /// The one-shot timer requested by `.scheduleTick` fired.
    mutating func tick(time: TimeInterval) -> [Effect] {
        guard case .hovering(let target, _, let since) = state else { return [] }
        // Timers can fire a hair early; a millisecond of slack.
        return time - since >= config.dwell - 0.001 ? arm(target) : [.scheduleTick(at: since + config.dwell)]
    }

    /// The mouse button went up: drop if armed, otherwise nothing.
    mutating func mouseUp() -> [Effect] {
        defer { state = .idle }
        if case .armed(let target) = state { return [.hideHighlight, .drop(target: target)] }
        return []
    }

    /// The drag was abandoned (for example, secure input turned on).
    mutating func cancel() -> [Effect] {
        defer { state = .idle }
        if case .armed = state { return [.hideHighlight] }
        return []
    }

    private mutating func startHovering(_ target: CGWindowID, _ cursor: CGPoint, _ time: TimeInterval) -> [Effect] {
        state = .hovering(target: target, anchor: cursor, since: time)
        return [.scheduleTick(at: time + config.dwell)]
    }

    private mutating func arm(_ target: CGWindowID) -> [Effect] {
        state = .armed(target: target)
        return [.showHighlight(target: target)]
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
