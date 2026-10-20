import AppKit
import ApplicationServices
import CoreGraphics

/// Accessibility (required) and Screen Recording (optional, PLAN.md §5.9) permission state.
///
/// Event-driven (PLAN.md §6.2 P2): re-checked when macOS posts its accessibility-trust change
/// notification, when Tabsome becomes active, and when an AX call reports the API disabled.
/// The only repeating check runs while onboarding is waiting for the user, and stops after.
@MainActor
@Observable
final class Permissions {
    private(set) var accessibility: Bool
    private(set) var screenRecording: Bool

    /// Called after `accessibility` changes.
    @ObservationIgnored var onAccessibilityChange: ((Bool) -> Void)?

    @ObservationIgnored private var waitTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            // The system updates trust slightly after posting; re-check a moment later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { self?.refresh() } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        guard ax != accessibility else { return }
        accessibility = ax
        Log.permissions.notice("accessibility \(ax ? "granted" : "missing")")
        FileLog.shared.write("permission accessibility=\(ax)")
        onAccessibilityChange?(ax)
    }

    /// Shows the system prompt once, which also adds Tabsome to the list in System Settings.
    func promptForAccessibility() {
        // The value of kAXTrustedCheckOptionPrompt (a C global that Swift 6 treats as mutable state).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        refresh()
    }

    /// While onboarding waits for the user to flip the switch: check once a second, then stop.
    func startWaiting() {
        guard waitTimer == nil else { return }
        waitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopWaiting() {
        waitTimer?.invalidate()
        waitTimer = nil
    }
}
