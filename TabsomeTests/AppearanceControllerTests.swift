import AppKit
import Testing
@testable import Tabsome

@MainActor
struct AppearanceControllerTests {
    @Test func modesMapToAppKitAppearances() {
        #expect(AppearanceMode.system.appearanceName == nil)
        #expect(AppearanceMode.light.appearanceName == .aqua)
        #expect(AppearanceMode.dark.appearanceName == .darkAqua)
    }

    @Test func defaultsToSystemAndPersistsTheChoice() throws {
        let suite = "AppearanceControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppearanceController(defaults: defaults)
        #expect(first.mode == .system)
        first.mode = .dark
        #expect(AppearanceController(defaults: defaults).mode == .dark)
    }
}
