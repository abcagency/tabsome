// TabsomeSpikes: one host app for all Phase 0 spikes, so permissions are granted once.
// Usage (via Spikes/run.sh): TabsomeSpikes <spike> [options]

import AppKit

setvbuf(stdout, nil, _IONBF, 0)

let spikes: [String: @MainActor (ArraySlice<String>) -> Void] = [
    "trust": { _ in
        log("AXIsProcessTrusted = \(AXIsProcessTrusted())")
        log("CGPreflightScreenCaptureAccess = \(CGPreflightScreenCaptureAccess())")
    },
    "grant": { _ in
        _ = requireAX()
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        log("Requested Accessibility and Screen Recording. Toggle TabsomeSpikes on in System Settings.")
    },
    "ax-matrix": S1.run,
    "window-id": S2.run,
    "zorder": S3.run,
    "drag-detect": S4.run,
    "drag-follow": S4b.run,
    "stacking": S5.run,
    "proxy": S6.run,
    "hung": S7.run,
    "metrics": S8.run,
    "drag-dest": S9.run,
    "shot": Shot.run,
    "tabdrag": TabDrag.run,
    "mouse": Mouse.run,
    "buttons": Buttons.run,
]

let args = Array(CommandLine.arguments.dropFirst())
let name = args.first ?? "trust"
guard spikes[name] != nil else {
    print("unknown spike \(name). known: \(spikes.keys.sorted().joined(separator: ", "))")
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        openLog(named: name)
        log("spike \(name) start; macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        spikes[name]!(args.dropFirst())
        // Spikes that need to keep running set keepAlive and call finish() themselves.
        if !keepAlive { finish() }
    }
}

nonisolated(unsafe) var keepAlive = false
func finish() {
    log("spike \(name) done")
    try? logHandle?.synchronize()
    exit(0)
}

let delegate = Delegate()
app.delegate = delegate
app.run()
