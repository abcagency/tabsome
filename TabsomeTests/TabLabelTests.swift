import CoreGraphics
import Testing
@testable import Tabsome

@MainActor
struct TabLabelTests {
    func entry(_ id: CGWindowID, app: String, pid: pid_t, title: String?) -> WindowRegistry.Entry {
        WindowRegistry.Entry(window: snapshot(id, pid: pid, title: title), app: .init(pid: pid, name: app, bundleID: nil))
    }

    @Test func differentAppsShowTheAppName() {
        let tabs = TabLabel.ghostTabs(existing: [entry(1, app: "Safari", pid: 10, title: "Apple")],
                                      adding: entry(2, app: "Finder", pid: 20, title: "Downloads"))
        #expect(tabs.map(\.label) == ["Safari", "Finder"])
        #expect(tabs.map(\.isNew) == [false, true])
    }

    @Test func sameAppTabsAddTheTitle() {
        let tabs = TabLabel.ghostTabs(existing: [entry(1, app: "Safari", pid: 10, title: "Apple")],
                                      adding: entry(2, app: "Safari", pid: 10, title: "Swift"))
        #expect(tabs.map(\.label) == ["Safari — Apple", "Safari — Swift"])
    }

    @Test func sameAppWithoutATitleFallsBackToTheName() {
        let tabs = TabLabel.ghostTabs(existing: [entry(1, app: "Notes", pid: 10, title: nil)],
                                      adding: entry(2, app: "Notes", pid: 10, title: ""))
        #expect(tabs.map(\.label) == ["Notes", "Notes"])
    }
}
