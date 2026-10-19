// Spike 1: AX can read, move and resize windows in the test apps.

import AppKit

enum S1 {
    static let targets: [(String, String)] = [
        ("Safari", "com.apple.Safari"),
        ("Safari Tech Preview", "com.apple.SafariTechnologyPreview"),
        ("Chrome", "com.google.Chrome"),
        ("Firefox", "org.mozilla.firefox"),
        ("Finder", "com.apple.finder"),
        ("Terminal", "com.apple.Terminal"),
        ("VS Code (Electron)", "com.microsoft.VSCode"),
        ("Slack (Electron)", "com.tinyspeck.slackmacgap"),
        ("Notes", "com.apple.Notes"),
        ("Xcode", "com.apple.dt.Xcode"),
        ("TextEdit", "com.apple.TextEdit"),
        ("SpikeHelper", "com.tabsome.spikehelper"),
    ]

    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        log("app | windows | std | pos settable | size settable | AXEnhancedUI | move call / land | resize call / land | resize result | frame round trip")
        for (label, bid) in targets {
            guard let app = runningApp(bid) else { log("\(label): NOT RUNNING / not installed"); continue }
            test(label: label, pid: app.processIdentifier)
        }
        // Java app: any running process whose executable is java.
        let javaApps = NSWorkspace.shared.runningApplications.filter {
            ($0.executableURL?.lastPathComponent ?? "").lowercased().contains("java")
        }
        if javaApps.isEmpty { log("Java app: none running") }
        for j in javaApps { test(label: "Java: \(j.localizedName ?? "?")", pid: j.processIdentifier) }
    }

    static func test(label: String, pid: pid_t) {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 1.0)
        let all = axWindows(pid: pid)
        let std = all.filter { axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
        let enhanced = axBool(appEl, "AXEnhancedUserInterface").map { "\($0)" } ?? "n/a"
        guard let w = std.first(where: { axBool($0, kAXMinimizedAttribute) != true }), let orig = axFrame(w) else {
            log("\(label): \(all.count) windows, \(std.count) standard; no usable standard window (subroles: \(all.map { axString($0, kAXSubroleAttribute) ?? "nil" }))")
            return
        }
        let posSet = axSettable(w, kAXPositionAttribute), sizeSet = axSettable(w, kAXSizeAttribute)

        // Move
        let target = CGPoint(x: orig.minX + 37, y: orig.minY + 23)
        var t = now()
        let me = axSetPosition(w, target)
        let moveCall = now() - t
        let moveLand = spinUntil(timeout: 1.5) { (axPoint(w).map { abs($0.x - target.x) < 1 && abs($0.y - target.y) < 1 }) ?? false }

        // Resize (shrink by an odd amount so grid-snapping apps reveal themselves)
        let want = CGSize(width: orig.width - 53, height: orig.height - 41)
        t = now()
        let se = axSetSize(w, want)
        let resizeCall = now() - t
        let resizeLand = spinUntil(timeout: 1.5) { (axSize(w).map { abs($0.width - want.width) < 1 && abs($0.height - want.height) < 1 }) ?? false }
        spin(0.15)
        let got = axSize(w) ?? .zero

        // Full frame round trip back to the original with size→position→size
        t = now()
        axSetFrame(w, orig)
        let back = spinUntil(timeout: 1.5) { axFrame(w).map { abs($0.minX - orig.minX) < 1 && abs($0.minY - orig.minY) < 1 && abs($0.width - orig.width) < 2 && abs($0.height - orig.height) < 2 } ?? false }
        let final = axFrame(w) ?? .zero

        log("\(label) | \(all.count) | \(std.count) | \(posSet) | \(sizeSet) | \(enhanced) | "
            + "\(me.name) \(ms(moveCall)) / \(moveLand.map(ms) ?? "NEVER") | "
            + "\(se.name) \(ms(resizeCall)) / \(resizeLand.map(ms) ?? "NO EXACT") | "
            + "asked \(Int(want.width))x\(Int(want.height)) got \(Int(got.width))x\(Int(got.height)) | "
            + "\(back.map(ms) ?? "MISMATCH") final \(Int(final.minX)),\(Int(final.minY)) \(Int(final.width))x\(Int(final.height)) vs orig \(Int(orig.minX)),\(Int(orig.minY)) \(Int(orig.width))x\(Int(orig.height))")
    }
}
