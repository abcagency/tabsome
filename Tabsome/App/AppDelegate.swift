import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        model.appearance.apply()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        FileLog.shared.write("launch version=\(version) accessibility=\(model.permissions.accessibility)")
        model.startIfPermitted()
        if model.needsOnboarding { model.showOnboarding() }
        #if DEBUG
        RegistryDump.handleLaunchArguments(model)
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Phase 3 adds "untab everything, close nothing" here (PLAN.md §5.12).
        model.stopAll()
        FileLog.shared.write("quit")
        FileLog.shared.flush()
    }
}
