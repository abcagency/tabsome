import AppKit
import ApplicationServices

// The third file allowed to call Accessibility APIs (PLAN.md §6.1 S1), for one narrow
// exception: reading the badges on the Dock's own items (§5.14). It reads nothing from any
// other app, and nothing from the Dock but its item list.

/// One app's item in the Dock: plain values, so it can cross threads and be faked in tests.
nonisolated struct DockItem: Sendable, Equatable {
    /// The app's bundle on disk.
    var url: URL?
    /// The app's name as the Dock shows it.
    var title: String?
    /// The badge text ("3", "!"), or nil when the icon has none.
    var badge: String?
}

/// Where badges come from: the Dock live, a fake in tests.
@MainActor
protocol DockBadgeSource: AnyObject {
    /// Reads the Dock's app items off the main thread; `done` comes back on the main actor
    /// (nil when the Dock couldn't be read).
    func read(_ done: @escaping @MainActor ([DockItem]?) -> Void)
}

/// Reads the Dock's app items on its own thread with the same 0.5 s timeout as every other AX
/// call (§6.2 P1), so a busy Dock never stalls the main thread.
@MainActor
final class DockBadgeReader: DockBadgeSource {
    private let worker = Worker()

    func read(_ done: @escaping @MainActor ([DockItem]?) -> Void) {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return done(nil)
        }
        worker.read(dockPID: dock) { items in
            DispatchQueue.main.async { MainActor.assumeIsolated { done(items) } }
        }
    }

    deinit { worker.stop() }

    nonisolated private final class Worker: @unchecked Sendable {
        // @unchecked: `list` and `listPID` are touched only on `thread`.
        private let thread = AXThread(name: "com.tabsome.ax.dock")
        private var list: AXUIElement?
        private var listPID: pid_t = 0

        init() { thread.start() }

        func stop() { thread.perform { self.list = nil; self.thread.finish() } }

        func read(dockPID: pid_t, done: @escaping @Sendable ([DockItem]?) -> Void) {
            thread.perform {
                // The Dock relaunches with a new pid (e.g. after a Dock setting changes).
                if self.listPID != dockPID { self.list = nil }
                if self.list == nil {
                    self.list = Self.itemList(dockPID: dockPID)
                    self.listPID = dockPID
                }
                guard let list = self.list, let items = Self.items(of: list) else {
                    self.list = nil
                    return done(nil)
                }
                done(items)
            }
        }

        /// The Dock's single AXList: its app items, then a separator, then folders and the Trash.
        private static func itemList(dockPID: pid_t) -> AXUIElement? {
            let dock = AXUIElementCreateApplication(dockPID)
            AXUIElementSetMessagingTimeout(dock, AXApp.messagingTimeout)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(dock, kAXChildrenAttribute as CFString, &value) == .success,
                  let children = value as? [AXUIElement] else { return nil }
            return children.first { role(of: $0) == kAXListRole }
        }

        private static func items(of list: AXUIElement) -> [DockItem]? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &value) == .success,
                  let children = value as? [AXUIElement] else { return nil }
            let names = [kAXSubroleAttribute, kAXURLAttribute, kAXTitleAttribute, "AXStatusLabel"] as CFArray
            return children.compactMap { item in
                var values: CFArray?
                guard AXUIElementCopyMultipleAttributeValues(item, names, [], &values) == .success,
                      let v = values as? [Any], v.count == 4,
                      v[0] as? String == "AXApplicationDockItem" else { return nil }
                return DockItem(url: v[1] as? URL, title: v[2] as? String, badge: v[3] as? String)
            }
        }

        private static func role(of element: AXUIElement) -> String? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
            return value as? String
        }
    }
}
