import Foundation

/// A small rotating log file for bug reports, in ~/Library/Logs/Tabsome (PLAN.md §3, §6.1 S8).
/// It records lifecycle events, counts, IDs, and errors only. **Never window titles or tab names**
/// (S4): callers pass already-safe text.
final class FileLog: Sendable {
    static let shared = FileLog(directory: AppPaths.logs)

    let directory: URL
    let maxBytes: Int
    let keep: Int
    private let queue = DispatchQueue(label: "com.tabsome.filelog", qos: .utility)

    init(directory: URL, maxBytes: Int = 1_000_000, keep: Int = 3) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.keep = keep
    }

    var currentFile: URL { directory.appending(path: "\(Brand.name).log") }

    func write(_ message: String) {
        let line = "\(Date.now.ISO8601Format()) \(message)\n"
        queue.async { self.append(line) }
    }

    /// Blocks until queued writes are on disk (used by tests and at quit).
    func flush() { queue.sync {} }

    private func append(_ line: String) {
        do {
            _ = try AppPaths.ensure(directory)
            let url = currentFile
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
               size + line.utf8.count > maxBytes {
                rotate()
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // Logging must never take the app down; drop the line.
        }
    }

    /// Tabsome.log → Tabsome.1.log → … → Tabsome.<keep>.log (the oldest is deleted).
    private func rotate() {
        let fm = FileManager.default
        func numbered(_ n: Int) -> URL { directory.appending(path: "\(Brand.name).\(n).log") }
        try? fm.removeItem(at: numbered(keep))
        if keep > 1 {
            for n in stride(from: keep - 1, through: 1, by: -1) where fm.fileExists(atPath: numbered(n).path) {
                try? fm.moveItem(at: numbered(n), to: numbered(n + 1))
            }
        }
        try? fm.moveItem(at: currentFile, to: numbered(1))
    }
}
