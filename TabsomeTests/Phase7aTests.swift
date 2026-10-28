import Foundation
import Testing
@testable import Tabsome

/// Report a Problem… (PLAN.md §7 Phase 7a).
struct ProblemReportTests {
    @Test func theDescriptionComesFirstThenFactsThenTheLog() {
        let body = ProblemReport.body(facts: [.init(name: "Tabsome", value: "1.0 (7)"), .init(name: "Displays", value: "2")],
                                      logs: [("Tabsome.1.log", "old line\n"), ("Tabsome.log", "new line")])
        let text = ProblemReport.text(description: "  Tabs vanished after sleep.  ", body: body)
        #expect(text.hasPrefix("Tabsome problem report\n\n## What happened\n\nTabs vanished after sleep.\n"))
        #expect(text.contains("Tabsome   1.0 (7)\nDisplays  2\n"))
        let old = text.range(of: "old line")!, new = text.range(of: "new line")!
        #expect(old.lowerBound < new.lowerBound)
        #expect(text.hasSuffix("--- Tabsome.log ---\nnew line\n"))
    }

    @Test func anEmptyDescriptionSaysSo() {
        #expect(ProblemReport.text(description: " \n", body: "").contains("(not described)"))
        #expect(ProblemReport.body(facts: [], logs: []).contains("(no log yet)"))
    }

    @Test func logsAreReadOldestFirstAndMissingOnesSkipped() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ProblemReportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for (name, text) in [("Tabsome.log", "c"), ("Tabsome.1.log", "b"), ("Tabsome.3.log", "a")] {
            try text.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        }
        let logs = ProblemReport.logs(in: dir, keep: 3)
        #expect(logs.map(\.name) == ["Tabsome.3.log", "Tabsome.1.log", "Tabsome.log"])
        #expect(logs.map(\.text) == ["a", "b", "c"])
    }

    @Test func fileNameCarriesTheDate() {
        let date = ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z")!
        #expect(ProblemReport.fileName(on: date) == "Tabsome Report 2026-10-28.txt")
    }
}
