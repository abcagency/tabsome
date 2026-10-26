import CoreGraphics
import Foundation

/// PLAN.md §6.2 P5: every frame Tabsome writes is remembered briefly, so the "moved"/"resized"
/// notifications it causes aren't mistaken for the user moving the window.
nonisolated struct ExpectedFrames {
    /// Apps round what they're given (Terminal: a few points), so match loosely.
    static let tolerance: CGFloat = 8
    static let lifetime: TimeInterval = 1.0

    private var entries: [CGWindowID: (frame: CGRect, until: TimeInterval)] = [:]

    mutating func expect(_ frame: CGRect, for id: CGWindowID, now: TimeInterval) {
        entries[id] = (frame, now + Self.lifetime)
    }

    /// True when this frame is (close to) one Tabsome asked for recently.
    func isExpected(_ frame: CGRect, for id: CGWindowID, now: TimeInterval) -> Bool {
        guard let e = entries[id], now <= e.until else { return false }
        return Self.close(frame, e.frame)
    }

    mutating func forget(_ id: CGWindowID) { entries[id] = nil }

    /// True when Tabsome wrote this window's frame within the last second.
    func wroteRecently(_ id: CGWindowID, now: TimeInterval) -> Bool {
        guard let e = entries[id] else { return false }
        return now <= e.until
    }

    static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = tolerance) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

/// PLAN.md §6.2 P4: another window manager (or the app itself) moving a member back each time
/// Tabsome places it. More than `limit` such moves within `period` means they're fighting, and
/// Tabsome lets go of the window. Tabsome's own timers re-place a window at most about four
/// times a second, so the period is 2 s rather than 1 s to still catch a fight that fast.
nonisolated struct FightDetector {
    static let limit = 3
    static let period: TimeInterval = 2

    private var moves: [CGWindowID: [TimeInterval]] = [:]

    /// Records a move against Tabsome; true once it adds up to a fight.
    mutating func record(_ id: CGWindowID, now: TimeInterval) -> Bool {
        var recent = (moves[id] ?? []).filter { now - $0 <= Self.period }
        recent.append(now)
        moves[id] = recent
        return recent.count > Self.limit
    }

    mutating func forget(_ id: CGWindowID) { moves[id] = nil }
}
