import Foundation
import Testing

/// PLAN.md §6.1 S1: the build-phase script must pass on the real tree and catch a violation.
struct AXUsageCheckTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func runCheck(root: URL) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [repoRoot.appending(path: "scripts/check-ax-usage.sh").path]
        p.environment = ["SRCROOT": root.path, "PATH": "/usr/bin:/bin"]
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    @Test func passesOnTheRealSources() throws {
        #expect(try runCheck(root: repoRoot) == 0)
    }

    @Test func failsWhenAXIsUsedElsewhere() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "axcheck-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let ui = tmp.appending(path: "Tabsome/UI")
        try FileManager.default.createDirectory(at: ui, withIntermediateDirectories: true)
        try "let x = AXUIElementCreateSystemWide()\n".write(to: ui.appending(path: "Bad.swift"), atomically: true, encoding: .utf8)
        #expect(try runCheck(root: tmp) == 1)
    }
}
