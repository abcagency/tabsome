#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only (PLAN.md §7 Phase 1): a readable dump of the window registry. This is the
/// one place window titles are shown; they never go to the logs (S4).
@MainActor
enum RegistryDump {
    static func text(_ registry: WindowRegistry) -> String {
        var lines = ["Tabsome window registry — \(Date.now.formatted(date: .abbreviated, time: .standard))",
                     "\(registry.apps.count) apps tracked, \(registry.windows.count) windows, \(registry.unresponsive.count) unresponsive", ""]
        for app in registry.apps.values.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let windows = registry.windows(of: app.pid)
            let flag = registry.unresponsive.contains(app.pid) ? "  [unresponsive]" : ""
            lines.append("\(app.name) (pid \(app.pid), \(app.bundleID ?? "no bundle ID"))\(flag): \(windows.count) window\(windows.count == 1 ? "" : "s")")
            for entry in windows {
                let w = entry.window
                let f = w.frame
                var tags: [String] = [w.subrole ?? "no subrole"]
                if registry.mainWindow[app.pid] == w.id { tags.append("main") }
                if w.isMinimized { tags.append("minimized") }
                if w.isFullScreen { tags.append("full screen") }
                lines.append(String(format: "  #%u  %5.0f,%5.0f  %4.0f×%-4.0f  ", w.id, f.minX, f.minY, f.width, f.height)
                             + "[\(tags.joined(separator: ", "))]  “\(w.title ?? "")”")
            }
        }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    static func write(_ registry: WindowRegistry) -> URL? {
        guard let dir = try? AppPaths.ensure(AppPaths.applicationSupport.appending(path: "Debug")) else { return nil }
        let url = dir.appending(path: "registry-dump.txt")
        try? text(registry).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static var window: NSWindow?

    static func show(_ registry: WindowRegistry) {
        write(registry)
        let content = ScrollView([.vertical, .horizontal]) {
            Text(text(registry))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding()
        }
        let w = window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Window Registry (Debug)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: content)
        if window == nil { w.center() }
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    /// `-TabsomeDebugDumpAfter <seconds>` writes the dump once the registry has settled;
    /// add `-TabsomeDebugQuitAfterDump YES` to quit afterwards (used for scripted checks).
    static func handleLaunchArguments(_ model: AppModel) {
        let defaults = UserDefaults.standard
        let delay = defaults.double(forKey: "TabsomeDebugDumpAfter")
        guard delay > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let url = write(model.registry)
                print("registry dump: \(url?.path ?? "failed"); accessibility=\(model.permissions.accessibility)")
                if defaults.bool(forKey: "TabsomeDebugQuitAfterDump") { NSApp.terminate(nil) }
            }
        }
    }
}
#endif
