import ServiceManagement

/// Settings › General › Launch at login (PLAN.md §7 Phase 6). The state always comes from
/// `SMAppService.mainApp.status`, so it stays right if the user changes it in System Settings.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
