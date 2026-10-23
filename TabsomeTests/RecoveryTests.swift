import CoreGraphics
import Foundation
import Testing
@testable import Tabsome

@MainActor
struct RecoveryTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager
    let safariFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.windowBounds = { _ in nil }
        manager.usableArea = { _ in CGRect(x: 0, y: 25, width: 1600, height: 1000) }
        registry.track(.init(pid: 101, name: "Safari", bundleID: "com.apple.Safari"))
        registry.track(.init(pid: 202, name: "Finder", bundleID: "com.apple.finder"))
        system.send(.appWindows(101, [snapshot(1, pid: 101, frame: safariFrame)]))
        system.send(.appWindows(202, [snapshot(2, pid: 202, frame: CGRect(x: 1000, y: 200, width: 500, height: 400))]))
    }

    func frames(_ id: CGWindowID) -> [CGRect] {
        system.commands.compactMap { cmd, window in
            if window == id, case .setFrame(let f) = cmd { return f } else { return nil }
        }
    }

    @Test func theStateHoldsIDsPidsBundleIDsAndFramesOnly() throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        let state = manager.recoveryState()
        let g = try #require(state.groups.first)
        #expect(state.groups.count == 1)
        #expect(g.outer == safariFrame)
        #expect(g.active == .init(id: 2, pid: 202, bundleID: "com.apple.finder"))
        #expect(g.others == [.init(id: 1, pid: 101, bundleID: "com.apple.Safari")])
        #expect(!g.minimized)
        // S4: nothing about titles or names reaches the file.
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(!json.contains("Doc"))
        #expect(!json.contains("title") && !json.contains("name"))
    }

    @Test func groupChangesAreSavedShortlyAfter() async throws {
        var saved: [RecoveryState] = []
        manager.onRecoveryStateChanged = { saved.append($0) }
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        #expect(saved.isEmpty) // coalesced, not on every change
        try await Task.sleep(for: .milliseconds(500))
        #expect(saved.count == 1)
        #expect(saved.last?.groups.count == 1)
    }

    @Test func recoveryUndoesTheGroupsTheWayQuitDoes() {
        let state = RecoveryState(groups: [.init(outer: safariFrame, active: .init(id: 2, pid: 202), others: [.init(id: 1, pid: 101)], minimized: false)])
        var finished = false
        manager.recover(state) { finished = true }
        #expect(finished)
        #expect(frames(2).last == safariFrame)
        #expect(frames(1).last == safariFrame.offsetBy(dx: 22, dy: 22))
        #expect(system.commands.contains { $0.0 == .raise && $0.1 == 2 })
        #expect(!system.commands.contains { $0.0 == .close })
        #expect(manager.groups.isEmpty)
    }

    @Test func aReusedWindowIDFromAnotherAppIsLeftAlone() {
        // Window 1 now belongs to Safari (101), but the file says it was another app's.
        let state = RecoveryState(groups: [.init(outer: safariFrame, active: .init(id: 2, pid: 202), others: [.init(id: 1, pid: 999)], minimized: false)])
        manager.recover(state, timeout: 0.05) {}
        #expect(frames(1).isEmpty)
    }

    @Test func recoveryWaitsForTheWindowsToAppear() {
        let state = RecoveryState(groups: [.init(outer: safariFrame, active: .init(id: 2, pid: 202), others: [.init(id: 7, pid: 303)], minimized: false)])
        var finished = false
        manager.recover(state, timeout: 5) { finished = true }
        #expect(!finished)
        registry.track(.init(pid: 303, name: "Notes", bundleID: "com.apple.Notes"))
        system.send(.appWindows(303, [snapshot(7, pid: 303, frame: CGRect(x: 1, y: 1, width: 200, height: 200))]))
        #expect(finished)
        #expect(frames(7).last == safariFrame.offsetBy(dx: 22, dy: 22))
    }

    @Test func aMinimizedGroupLeavesItsWindowInTheDock() {
        let state = RecoveryState(groups: [.init(outer: safariFrame, active: .init(id: 2, pid: 202), others: [.init(id: 1, pid: 101)], minimized: true)])
        manager.recover(state) {}
        #expect(frames(2).isEmpty)
        #expect(frames(1).last == safariFrame)
        #expect(!system.commands.contains { $0.0 == .raise })
    }

    @Test func aQuitRestoreThatRunsOutOfTimeKeepsTheFile() async throws {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        system.hung = [1]
        var result: Bool?
        manager.restoreAll(timeout: 0.1) { result = $0 }
        for _ in 0..<40 where result == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(result == false)
    }

    @Test func aQuitRestoreWhereEveryWindowAnswers() {
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        var result: Bool?
        manager.restoreAll(timeout: 2) { result = $0 }
        #expect(result == true)
    }
}

struct RecoveryFileTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "tabsome-tests-\(UUID().uuidString)/recovery.json")

    @Test func roundTripsAndDeletesWhenEmpty() {
        let state = RecoveryState(groups: [.init(outer: CGRect(x: 1, y: 2, width: 3, height: 4), active: .init(id: 9, pid: 8, bundleID: "b"), others: [], minimized: true)])
        RecoveryFile.save(state, to: url)
        #expect(RecoveryFile.load(from: url) == state)
        RecoveryFile.save(RecoveryState(), to: url)
        #expect(RecoveryFile.load(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
