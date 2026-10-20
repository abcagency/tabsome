import CoreGraphics
import Testing
@testable import Tabsome

struct EligibilityTests {
    func window(subrole: String = "AXStandardWindow", standard: Bool = true, minimized: Bool = false, fullScreen: Bool = false) -> WindowSnapshot {
        WindowSnapshot(id: 1, pid: 2, title: nil, frame: .zero, subrole: subrole, isStandard: standard,
                       isMinimized: minimized, isFullScreen: fullScreen, isMain: false)
    }

    @Test func standardWindowsOfOrdinaryAppsQualify() {
        #expect(Eligibility.canTab(window(), bundleID: "com.apple.Safari"))
    }

    @Test func nonStandardMinimizedAndFullScreenDoNot() {
        #expect(!Eligibility.canTab(window(subrole: "AXDialog", standard: false), bundleID: "com.apple.Safari"))
        #expect(!Eligibility.canTab(window(minimized: true), bundleID: "com.apple.Safari"))
        #expect(!Eligibility.canTab(window(fullScreen: true), bundleID: "com.apple.Safari"))
    }

    @Test(arguments: ["com.apple.SecurityAgent", "com.apple.keychainaccess", "com.1password.1password"])
    func securitySensitiveAppsNever(bundleID: String) {
        #expect(!Eligibility.canTab(window(), bundleID: bundleID))
    }
}
