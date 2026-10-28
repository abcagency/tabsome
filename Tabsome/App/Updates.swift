import AppKit
import Sparkle

/// Updates through Sparkle 2 (PLAN.md §7 Phase 7c, §6.1 S2): the feed on GitHub Pages over HTTPS,
/// and only updates signed with Tabsome's EdDSA key are installed. Sparkle asks once, on the
/// second launch, whether to check automatically; Settings › About changes that later.
///
/// Off in Tabsome Dev: a debug build must never replace itself with a release.
///
/// Tabsome lives in the menu bar, so an update found by a scheduled check while the user is busy
/// in another app doesn't open a window over their work. The menu offers it instead ("gentle
/// reminders", Sparkle's recommendation for background apps).
@MainActor
@Observable
final class Updates: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    #if DEBUG
    static let isAvailable = false
    #else
    static let isAvailable = true
    #endif

    /// A scheduled check found an update the user hasn't looked at yet.
    private(set) var updateWaiting = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: Self.isAvailable, updaterDelegate: self, userDriverDelegate: self)
    }

    var canCheck: Bool { Self.isAvailable && (controller?.updater.canCheckForUpdates ?? false) }

    func checkForUpdates() {
        guard Self.isAvailable else { return }
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                NSApp.activate()
            } else {
                updateWaiting = true
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { updateWaiting = false }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { updateWaiting = false }
    }

    // MARK: SPUUpdaterDelegate

    /// Sparkle quits Tabsome to install, which goes through the same restore as Quit (§5.12):
    /// every group is undone and nothing is closed, then the new version opens.
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        FileLog.shared.write("update: relaunching into the new version")
    }
}
