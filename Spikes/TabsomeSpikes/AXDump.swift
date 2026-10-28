// Tooling: prints what VoiceOver sees in one app's windows (Phase 6d).
//   axdump <bundle id or pid> [maxDepth]     role, subrole, label, value, help, and actions
//   axdump <bundle id or pid> press <label> [n] [action]   performs an action (default AXPress)
//                                                        on the nth element with that label
// Labels can include window titles, so the output goes to the spike log only (not product code).

import AppKit
import ApplicationServices

@MainActor
enum AXDump {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        let target = args.first ?? "com.tabsome.app.dev"
        let depth = args.dropFirst().first.flatMap(Int.init) ?? 12
        let pid = pid_t(target) ?? NSRunningApplication.runningApplications(withBundleIdentifier: target).first?.processIdentifier
        guard let pid else { return log("no app \(target)") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        if args.dropFirst().first == "press" {
            let a = Array(args.dropFirst(2))
            guard let label = a.first else { return log("press needs a label") }
            let n = a.count > 1 ? Int(a[1]) ?? 1 : 1
            let action = a.count > 2 ? a[2] : kAXPressAction
            // Matches the label (or the title, for buttons without one); "subrole:AXCloseButton" matches by subrole.
            let found = children(app, kAXWindowsAttribute).flatMap { all($0) }.filter {
                label.hasPrefix("subrole:") ? string($0, kAXSubroleAttribute) == String(label.dropFirst(8))
                    : (string($0, kAXDescriptionAttribute) ?? string($0, kAXTitleAttribute)) == label
            }
            guard found.count >= n else { return log("found \(found.count) \"\(label)\"") }
            var names: CFArray?
            AXUIElementCopyActionNames(found[n - 1], &names)
            let match = (names as? [String] ?? []).first { $0 == action || $0.hasPrefix("Name:\(action)\n") } ?? action
            log("perform \(action) on \(label) #\(n): \(AXUIElementPerformAction(found[n - 1], match as CFString).rawValue)")
            return
        }
        for window in children(app, kAXWindowsAttribute) {
            dump(window, level: 0, maxDepth: depth)
        }
    }

    private static func all(_ e: AXUIElement) -> [AXUIElement] {
        [e] + children(e).flatMap { all($0) }
    }

    private static func children(_ e: AXUIElement, _ attr: String = kAXChildrenAttribute) -> [AXUIElement] {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(e, attr as CFString, &v)
        return v as? [AXUIElement] ?? []
    }

    private static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    private static func dump(_ e: AXUIElement, level: Int, maxDepth: Int) {
        var names: CFArray?
        AXUIElementCopyActionNames(e, &names)
        let actions = (names as? [String] ?? []).map { a -> String in
            var d: CFString?
            AXUIElementCopyActionDescription(e, a as CFString, &d)
            return a.hasPrefix("Name:") ? String(a.dropFirst(5).prefix { $0 != "\n" }) : (d as String? ?? a)
        }
        let parts = [
            string(e, kAXRoleAttribute),
            string(e, kAXSubroleAttribute).map { "(\($0))" },
            string(e, kAXTitleAttribute).map { "title=\"\($0)\"" },
            string(e, kAXDescriptionAttribute).map { "label=\"\($0)\"" },
            string(e, kAXValueAttribute).map { "value=\"\($0)\"" },
            string(e, kAXHelpAttribute).map { "help=\"\($0)\"" },
            string(e, kAXSelectedAttribute).flatMap { $0 == "1" ? "selected" : nil },
            actions.isEmpty ? nil : "actions=[\(actions.joined(separator: ", "))]",
        ].compactMap { $0 }
        log(String(repeating: "  ", count: level) + parts.joined(separator: " "))
        guard level < maxDepth else { return }
        for c in children(e) { dump(c, level: level + 1, maxDepth: maxDepth) }
    }
}
