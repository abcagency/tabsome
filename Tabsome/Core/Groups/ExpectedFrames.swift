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

    static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = tolerance) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
