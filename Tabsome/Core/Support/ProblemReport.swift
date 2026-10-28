import Foundation

/// Report a Problem… (PLAN.md §7 Phase 7a, §6.1 S4): the user's own words, a few facts about
/// this Mac and Tabsome's state, and the whole rotating log, oldest first. Nothing in it can hold
/// a window title or tab name: the log never records them, and the facts are counts and
/// settings. The user sees all of it before saving, and sends it themselves.
nonisolated enum ProblemReport {
    struct Fact: Equatable {
        let name: String
        let value: String
    }

    /// The whole report: the title, the user's description, then `body`.
    static func text(description: String, body: String) -> String {
        let words = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(Brand.name) problem report\n\n## What happened\n\n" + (words.isEmpty ? "(not described)" : words) + "\n\n" + body
    }

    /// Everything after the description: the facts, then the log.
    static func body(facts: [Fact], logs: [(name: String, text: String)]) -> String {
        var out = "## This Mac and Tabsome\n\n"
        let width = facts.map(\.name.count).max() ?? 0
        for f in facts {
            out += f.name.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + f.value + "\n"
        }
        out += "\n## Log\n"
        if logs.isEmpty { out += "\n(no log yet)\n" }
        for log in logs {
            out += "\n--- \(log.name) ---\n" + log.text
            if !log.text.hasSuffix("\n") { out += "\n" }
        }
        return out
    }

    /// The log files in `directory`, oldest first: Tabsome.3.log … Tabsome.1.log, then Tabsome.log.
    static func logs(in directory: URL, keep: Int = 3) -> [(name: String, text: String)] {
        let names = stride(from: keep, through: 1, by: -1).map { "\(Brand.name).\($0).log" } + ["\(Brand.name).log"]
        return names.compactMap { name in
            guard let text = try? String(contentsOf: directory.appending(path: name), encoding: .utf8) else { return nil }
            return (name, text)
        }
    }

    /// "Tabsome Report 2026-10-28.txt"
    static func fileName(on date: Date = .now) -> String {
        "\(Brand.name) Report \(date.formatted(.iso8601.year().month().day())).txt"
    }
}
