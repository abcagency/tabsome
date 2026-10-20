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

    /// Untab everything, close nothing (PLAN.md §5.12): reply later, once every window is back,
    /// or after 2 s so a hung app can't stop Tabsome from quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isRunningTests, !model.groups.groups.isEmpty else { return .terminateNow }
        model.restoreAndStop {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopAll()
        FileLog.shared.write("quit")
        FileLog.shared.flush()
    }
}
