import SwiftUI

@main
struct TabsomeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(model: delegate.model)
        } label: {
            MenuBarLabel(permissions: delegate.model.permissions)
        }
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
