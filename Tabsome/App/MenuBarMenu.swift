import SwiftUI

/// The short menu from PLAN.md §1: Settings… and Quit, plus "Grant Accessibility Permission…"
/// at the top while the permission is missing, and "Update Available…" while a scheduled check
/// has found one (Phase 7c).
struct MenuBarMenu: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !model.permissions.accessibility {
            Button("Grant Accessibility Permission…") { model.showOnboarding() }
            Divider()
        }
        if model.updates.updateWaiting {
            Button("Update Available…") { model.updates.checkForUpdates() }
            Divider()
        }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        #if DEBUG
        Divider()
        Button("Dump Window Registry (Debug)") { RegistryDump.show(model.registry) }
        #endif
        Divider()
        Button("Quit \(Brand.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Template icon, so it follows the menu bar's own look; badged while Accessibility is missing.
struct MenuBarLabel: View {
    let permissions: Permissions
    /// Dimmed while paused (PLAN.md §1).
    let paused: Bool

    var body: some View {
        Image(nsImage: MenuBarIconImage.image(badged: !permissions.accessibility, dimmed: paused))
            .accessibilityLabel(!permissions.accessibility ? "\(Brand.name), Accessibility permission needed" : paused ? "\(Brand.name), paused" : Brand.name)
            #if DEBUG
            .modifier(DebugSettingsHook())
            #endif
    }
}

enum MenuBarIconImage {
    static func image(badged: Bool, dimmed: Bool = false) -> NSImage {
        let base = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: Brand.name)!
        guard badged || dimmed else {
            base.isTemplate = true
            return base
        }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            // A template's alpha is its ink: drawn at partial opacity, the menu bar shows it dimmed.
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.4 : 1)
            guard badged else { return true }
            // A small dot at the bottom right, knocked out of the glyph so it reads at 16 pt.
            let dot = NSRect(x: size.width - 7, y: 0, width: 7, height: 7)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
