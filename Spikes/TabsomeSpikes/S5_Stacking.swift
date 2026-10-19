// Spike 5: stacking concealment. Two windows from different apps at the identical frame;
// switching = AXRaise (+ app activation). Measures switch latency and which activation
// method works for a background (LSUIElement) app under macOS cooperative activation.
//
//   stacking [bidA bidB]          automated: 3 methods × 12 switches each
//   stacking demo [bidA bidB]     switch every 0.8 s for 12 s so a human can watch for flicker

import AppKit

enum S5 {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        let demo = args.first == "demo"
        let bids = Array(args.filter { $0.contains(".") })
        let aBID = bids.first ?? "com.apple.Terminal", bBID = bids.dropFirst().first ?? "com.apple.finder"
        guard let aApp = runningApp(aBID), let bApp = runningApp(bBID),
              let aW = axStandardWindows(pid: aApp.processIdentifier).first,
              let bW = axStandardWindows(pid: bApp.processIdentifier).first,
              let aID = windowID(aW), let bID = windowID(bW) else { log("need windows in \(aBID) and \(bBID)"); return }
        let aOrig = axFrame(aW)!, bOrig = axFrame(bW)!
        let f = CGRect(x: 280, y: 200, width: 900, height: 560)
        axSetFrame(aW, f); axSetFrame(bW, f)
        spin(0.4)
        let fa = axFrame(aW)!, fb = axFrame(bW)!
        log("stacked frames: A \(fa) B \(fb) identical=\(fa == fb)")

        let members: [(AXUIElement, CGWindowID, pid_t, String)] = [
            (aW, aID, aApp.processIdentifier, aApp.localizedName ?? "A"),
            (bW, bID, bApp.processIdentifier, bApp.localizedName ?? "B"),
        ]
        func frontIs(_ id: CGWindowID) -> Bool {
            let l = cgWindows().filter { $0.layer == 0 && ($0.id == aID || $0.id == bID) }
            return l.first?.id == id
        }

        if demo {
            // Labeled variants for a human to compare, plus automatic "show-through" sampling:
            // at the stack's centre and four edge points, is the top window ever neither member?
            let probes = [CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.minX + 3, y: f.midY), CGPoint(x: f.maxX - 3, y: f.midY),
                          CGPoint(x: f.midX, y: f.minY + 3), CGPoint(x: f.midX, y: f.maxY - 3)]
            func showThrough(_ ids: Set<CGWindowID>) -> Bool {
                let l = cgWindows().filter { $0.layer == 0 && $0.pid != getpid() }
                return probes.contains { pt in l.first(where: { $0.bounds.contains(pt) }).map { !ids.contains($0.id) } ?? true }
            }
            func runVariant(_ label: String, _ ms_: [(AXUIElement, CGWindowID, pid_t, String)], _ step: (AXUIElement, pid_t) -> Void) {
                banner(label)
                spin(1.2)
                let ids = Set(ms_.map(\.1))
                var samples = 0, bad = 0
                for i in 0..<8 {
                    let m = ms_[i % 2]
                    step(m.0, m.2)
                    let end = now() + 0.8
                    while now() < end { samples += 1; if showThrough(ids) { bad += 1 }; spin(0.002) }
                }
                log("\(label): show-through samples \(bad)/\(samples)")
            }
            log("DEMO: 4 labelled variants, ~8 s each. Watch the banner at the top of the main display.")
            runVariant("1 of 4: Terminal + Finder, raise then activate", members) { w, pid in activate(window: w, pid: pid, method: .nsRunningApp) }
            runVariant("2 of 4: Terminal + Finder, activate then raise", members) { w, pid in
                NSRunningApplication(processIdentifier: pid)?.activate()
                spinUntil(timeout: 0.3) { frontmostPID() == pid }
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
            // Same-size pair: Safari + VS Code at an identical frame.
            if let s = runningApp("com.apple.Safari"), let c = runningApp("com.microsoft.VSCode"),
               let sw = axStandardWindows(pid: s.processIdentifier).first, let cw = axStandardWindows(pid: c.processIdentifier).first,
               let sID = windowID(sw), let cID = windowID(cw) {
                let so = axFrame(sw)!, co = axFrame(cw)!
                axSetFrame(aW, aOrig); axSetFrame(bW, bOrig)
                axSetFrame(sw, f); axSetFrame(cw, f); spin(0.4)
                log("pair frames: Safari \(axFrame(sw)!) Code \(axFrame(cw)!)")
                let pair = [(sw, sID, s.processIdentifier, "Safari"), (cw, cID, c.processIdentifier, "Code")]
                runVariant("3 of 4: Safari + VS Code (identical sizes), raise then activate", pair) { w, pid in activate(window: w, pid: pid, method: .nsRunningApp) }
                runVariant("4 of 4: Safari + VS Code, AX frontmost + raise", pair) { w, pid in activate(window: w, pid: pid, method: .axFrontmost) }
                axSetFrame(sw, so); axSetFrame(cw, co)
            }
            bannerPanel?.orderOut(nil)
        } else {
            for method in ActivateMethod.allCases {
                var lat: [Double] = [], frontOK = 0, appOK = 0
                for i in 0..<12 {
                    let m = members[(i + 1) % 2]
                    let t = now()
                    activate(window: m.0, pid: m.2, method: method)
                    if let d = spinUntil(timeout: 1, poll: 0.001, { frontIs(m.1) }) { lat.append(d); frontOK += 1 }
                    spinUntil(timeout: 0.5) { frontmostPID() == m.2 }
                    if frontmostPID() == m.2 { appOK += 1 }
                    _ = t
                    spin(0.15)
                }
                let s = lat.sorted()
                log("\(method.rawValue): window on top \(frontOK)/12, app frontmost \(appOK)/12, latency median \(s.isEmpty ? "-" : ms(s[s.count / 2])) max \(s.last.map(ms) ?? "-")")
            }
            // Does the covered window keep its frame while hidden? (some apps nudge on deactivate)
            spin(0.3)
            log("after switching: A \(axFrame(aW)!) B \(axFrame(bW)!)")
        }
        axSetFrame(aW, aOrig); axSetFrame(bW, bOrig)
    }
}
