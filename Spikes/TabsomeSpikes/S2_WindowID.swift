// Spike 2: _AXUIElementGetWindow maps AX windows to CGWindowIDs reliably.

import AppKit

enum S2 {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        let cgAll = cgWindows(onScreenOnly: false)
        let byID = Dictionary(cgAll.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var total = 0, mapped = 0, pidOK = 0, boundsOK = 0, failed: [String] = []
        var callTimes: [Double] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            let appEl = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appEl, 0.5)
            let wins = axWindows(pid: pid)
            var axMatchedIDs = Set<CGWindowID>()
            for w in wins {
                total += 1
                let t = now()
                let id = windowID(w)
                callTimes.append(now() - t)
                guard let id else { failed.append("\(app.localizedName ?? "?"): no id (subrole \(axString(w, kAXSubroleAttribute) ?? "nil"))"); continue }
                mapped += 1
                axMatchedIDs.insert(id)
                guard let cg = byID[id] else { failed.append("\(app.localizedName ?? "?"): id \(id) not in CG list"); continue }
                if cg.pid == pid { pidOK += 1 } else { failed.append("\(app.localizedName ?? "?"): id \(id) pid mismatch \(cg.pid)") }
                if let f = axFrame(w), abs(f.minX - cg.bounds.minX) < 1, abs(f.minY - cg.bounds.minY) < 1,
                   abs(f.width - cg.bounds.width) < 1, abs(f.height - cg.bounds.height) < 1 {
                    boundsOK += 1
                } else {
                    failed.append("\(app.localizedName ?? "?"): id \(id) bounds differ AX \(axFrame(w).map { "\($0)" } ?? "nil") CG \(cg.bounds) minimized=\(axBool(w, kAXMinimizedAttribute) ?? false)")
                }
            }
            // Reverse direction: on-screen layer-0 CG windows of this app with no AX window.
            let cgOnScreen = cgAll.filter { $0.pid == pid && $0.layer == 0 && $0.onScreen && $0.bounds.width > 50 && $0.bounds.height > 50 }
            let orphans = cgOnScreen.filter { !axMatchedIDs.contains($0.id) }
            log("\(app.localizedName ?? "?"): AX windows \(wins.count), on-screen CG windows \(cgOnScreen.count), CG without AX \(orphans.count)")
        }
        let avg = callTimes.isEmpty ? 0 : callTimes.reduce(0, +) / Double(callTimes.count)
        log("TOTAL AX windows \(total): id mapped \(mapped), pid matches \(pidOK), bounds match \(boundsOK)")
        log(String(format: "_AXUIElementGetWindow avg %.1f µs, max %.1f µs", avg * 1e6, (callTimes.max() ?? 0) * 1e6))
        for f in failed { log("  note: \(f)") }
    }
}
