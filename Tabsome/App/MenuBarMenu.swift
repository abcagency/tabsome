import SwiftUI

/// The short menu from PLAN.md §1: Settings… and Quit, plus "Grant Accessibility Permission…"
/// at the top while the permission is missing.
struct MenuBarMenu: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !model.permissions.accessibility {
            Button("Grant Accessibility Permission…") { model.showOnboarding() }
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

    var body: some View {
        Image(nsImage: MenuBarIconImage.image(badged: !permissions.accessibility))
            .accessibilityLabel(permissions.accessibility ? Brand.name : "\(Brand.name), Accessibility permission needed")
            #if DEBUG
            .modifier(DebugSettingsHook())
            #endif
    }
}

enum MenuBarIconImage {
    static func image(badged: Bool) -> NSImage {
        let base = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: Brand.name)!
        guard badged else {
            base.isTemplate = true
            return base
        }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
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
