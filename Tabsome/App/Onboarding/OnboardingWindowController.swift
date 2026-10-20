import AppKit
import SwiftUI

/// Hosts the onboarding walkthrough in a plain AppKit window, so it can open at launch
/// before any SwiftUI scene exists (Tabsome has no Dock icon or main window).
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private unowned let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(model: model) { [weak self] in self?.finish() })
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        model.onboardingCompleted = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.permissions.stopWaiting()
        window = nil
    }
}
