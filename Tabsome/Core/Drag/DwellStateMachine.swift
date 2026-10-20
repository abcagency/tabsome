import CoreGraphics
import Foundation

/// What's under the cursor during a drag (PLAN.md §5.2).
nonisolated enum DwellTarget: Equatable {
    /// The middle zone of an eligible window (or of a group's active window).
    case middle(CGWindowID)
    /// An existing group's tab strip, at an insertion index. Identified by the group's active window.
    case strip(CGWindowID, index: Int)
}

/// "Pause for a moment" (PLAN.md §5.3). Pure: it takes the cursor, the time, and what's under
/// the cursor, and returns effects for the caller to perform.
///
/// Over a window's middle the cursor has to stay within `jitter` points for `dwell` seconds. The
/// cursor doesn't move while the user pauses, so no events arrive: the machine asks for a
/// one-shot `tick` at the moment the dwell would complete. Over a tab strip there's no wait,
/// like dragging a tab into another browser window (§5.2).
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
        case armedOnStrip(target: CGWindowID, index: Int)
    }

    enum Effect: Equatable {
        case showHighlight(target: CGWindowID)
        case hideHighlight
        /// The insertion marker in a strip, between tabs (§5.2).
        case showInsertion(target: CGWindowID, index: Int)
        case hideInsertion(target: CGWindowID)
        /// Call `tick(time:)` at this time (replacing any earlier request).
        case scheduleTick(at: TimeInterval)
        /// Mouse up while armed over a middle: tab into that window (or its group), at the end.
        case drop(target: CGWindowID)
        /// Mouse up over a strip: insert at that position.
        case dropOnStrip(target: CGWindowID, index: Int)
    }

    let config: Config
    private(set) var state = State.idle

    init(config: Config = Config()) {
        self.config = config
    }

    /// The cursor moved (or the target under it was re-resolved).
    mutating func update(cursor: CGPoint, time: TimeInterval, target: DwellTarget?) -> [Effect] {
        var effects = leave(unless: target)
        switch (state, target) {
        case (_, nil):
            state = .idle
        case (.armedOnStrip(let current, let index), .strip(let t, let i)) where current == t:
            if index != i {
                state = .armedOnStrip(target: t, index: i)
                effects.append(.showInsertion(target: t, index: i))
            }
        case (_, .strip(let t, let i)):
            state = .armedOnStrip(target: t, index: i)
            effects.append(.showInsertion(target: t, index: i))
        case (.armed(let current), .middle(let t)) where current == t:
            break
        case (.hovering(let current, let anchor, let since), .middle(let t)) where current == t:
            if distance(cursor, anchor) >= config.jitter {
                effects += startHovering(t, cursor, time)
            } else if time - since >= config.dwell {
                effects += arm(t)
            }
        case (_, .middle(let t)):
            effects += startHovering(t, cursor, time)
        }
        return effects
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
        switch state {
        case .armed(let t): return [.hideHighlight, .drop(target: t)]
        case .armedOnStrip(let t, let i): return [.hideInsertion(target: t), .dropOnStrip(target: t, index: i)]
        default: return []
        }
    }

    /// The drag was abandoned (for example, secure input turned on).
    mutating func cancel() -> [Effect] {
        defer { state = .idle }
        return leave(unless: nil)
    }

    /// Hides whatever the current state shows, unless the new target keeps showing it.
    private func leave(unless next: DwellTarget?) -> [Effect] {
        switch state {
        case .armed(let t):
            if case .middle(t) = next { return [] }
            return [.hideHighlight]
        case .armedOnStrip(let t, _):
            if case .strip(t, _) = next { return [] }
            return [.hideInsertion(target: t)]
        default:
            return []
        }
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
