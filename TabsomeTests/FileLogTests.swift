import Foundation
import Testing
@testable import Tabsome

struct FileLogTests {
    @Test func rotatesAndKeepsALimitedNumberOfFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FileLogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = FileLog(directory: dir, maxBytes: 200, keep: 2)
        for i in 0..<40 { log.write("event number \(i) with some padding text") }
        log.flush()

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(files == ["Tabsome.1.log", "Tabsome.2.log", "Tabsome.log"])
        for f in files {
            let size = try FileManager.default.attributesOfItem(atPath: dir.appending(path: f).path)[.size] as? Int ?? 0
            #expect(size <= 200)
        }
        let newest = try String(contentsOf: log.currentFile, encoding: .utf8)
        #expect(newest.contains("event number 39"))
    }
}

struct TestRunPathsTests {
    @Test func testRunsNeverWriteIntoTheUsersFolders() {
        #expect(AppPaths.isRunningTests)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for url in [AppPaths.logs, AppPaths.applicationSupport, FileLog.shared.directory, RecoveryFile.url] {
            #expect(!url.path.hasPrefix(home + "/Library/"))
        }
    }
}
