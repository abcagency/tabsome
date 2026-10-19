// Spike 3 (biggest risk): keep a normal-level NSPanel just above another app's window with
// order(.above, relativeTo:), while other apps' windows can still cover it.
//
// Target window W = Terminal, covering window F = Finder (override: zorder <targetBID> <coverBID>).
// Options: --hold N keeps the live strip (follows W, re-orders on focus changes) for N seconds
// so a human can poke at it.

import AppKit

enum S3 {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        let positional = args.filter { !$0.hasPrefix("--") && Double($0) == nil }
        let targetBID = positional.first ?? "com.apple.Terminal"
        let coverBID = positional.dropFirst().first ?? "com.apple.finder"
        let hold = args.firstIndex(of: "--hold").flatMap { i in args.index(after: i) < args.endIndex ? Double(args[args.index(after: i)]) : nil } ?? 0

        guard let tApp = runningApp(targetBID), let fApp = runningApp(coverBID),
              let tW = axStandardWindows(pid: tApp.processIdentifier).first,
              let fW = axStandardWindows(pid: fApp.processIdentifier).first,
              let tID = windowID(tW), let fID = windowID(fW) else {
            log("need a standard window in \(targetBID) and \(coverBID)"); return
        }
        let tPID = tApp.processIdentifier, fPID = fApp.processIdentifier
        let tOrig = axFrame(tW)!, fOrig = axFrame(fW)!

        let wFrame = CGRect(x: 300, y: 260, width: 760, height: 420)
        axSetFrame(tW, wFrame)
        axSetFrame(fW, CGRect(x: 520, y: 140, width: 600, height: 420)) // overlaps the strip area
        spin(0.3)

        activate(window: tW, pid: tPID, method: .nsRunningApp)
        spinUntil(timeout: 2) { frontmostPID() == tPID }
        spin(0.2)

        let stripFrame = { (w: CGRect) in CGRect(x: w.minX, y: w.minY - 28, width: w.width, height: 28) }
        let p = makeStripPanel(frameCG: stripFrame(wFrame), color: NSColor.systemRed.withAlphaComponent(0.85))
        let names: [CGWindowID: String] = [CGWindowID(p.windowNumber): "STRIP", tID: "W(\(tApp.localizedName ?? ""))", fID: "F(\(fApp.localizedName ?? ""))"]
        let order = { describeOrder(names) }

        func idx(_ id: CGWindowID) -> Int { zIndex(id, in: cgWindows()) ?? -1 }
        var pID: CGWindowID { CGWindowID(p.windowNumber) }
        var results: [String] = []
        func check(_ label: String, _ ok: Bool) { results.append("\(ok ? "PASS" : "FAIL") \(label)"); log("\(ok ? "PASS" : "FAIL") \(label) — \(order())") }

        // 1. Place strip directly above W (W frontmost).
        p.order(.above, relativeTo: Int(tID))
        spin(0.15)
        log("panel windowNumber \(p.windowNumber), visible \(p.isVisible)")
        check("1 strip directly above W after order(.above, relativeTo: W)", idx(pID) == idx(tID) - 1)

        // 2. Another app comes to front over the strip area: it must cover the strip.
        activate(window: fW, pid: fPID, method: .nsRunningApp)
        spinUntil(timeout: 2) { frontmostPID() == fPID }
        spin(0.25)
        check("2 F (now front) covers the strip", idx(fID) < idx(pID))
        check("2 strip still directly above W", idx(pID) == idx(tID) - 1)

        // 2b. Does relativeTo really honour a foreign window? Re-order while F is in front:
        //     strip must stay BEHIND F (an implementation that just ordersFront would jump above F).
        p.order(.above, relativeTo: Int(tID))
        spin(0.15)
        check("2b re-order while W is behind F keeps strip behind F (relativeTo honoured)", idx(fID) < idx(pID) && idx(pID) == idx(tID) - 1)

        // 3. W's app re-activates (user clicks W / Cmd-Tab). W jumps above F; the strip does not
        //    move by itself. Measure how quickly a notification lets us fix it.
        var reorderedAt: Double? = nil
        var notifAt: Double? = nil
        // Settle burst: after any focus/activation notification, check the CG order once per
        // frame for up to 300 ms and re-order whenever the strip is not directly above W.
        var burstUntil = 0.0, burstFixes = 0
        var burstTimer: Timer?
        func settle() {
            burstUntil = now() + 0.3
            guard burstTimer == nil else { return }
            burstTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { t in
                let l = cgWindows()
                if let iW = zIndex(tID, in: l), zIndex(pID, in: l) != iW - 1 {
                    p.order(.above, relativeTo: Int(tID)); burstFixes += 1
                    reorderedAt = now()
                }
                if now() > burstUntil { t.invalidate(); burstTimer = nil }
            }
        }
        let obs = AXObs(pid: tPID) { notif, _ in
            if notifAt == nil { notifAt = now() }
            p.order(.above, relativeTo: Int(tID))
            if reorderedAt == nil { reorderedAt = now() }
            settle()
            log("  AX notification \(notif) → re-ordered strip + settle burst")
        }
        let tAppEl = AXUIElementCreateApplication(tPID)
        obs?.add(tAppEl, kAXApplicationActivatedNotification)
        obs?.add(tAppEl, kAXFocusedWindowChangedNotification)
        obs?.add(tAppEl, kAXMainWindowChangedNotification)
        obs?.add(tW, kAXMovedNotification)
        obs?.add(tW, kAXResizedNotification)
        var wsAt: Double? = nil
        let wsObs = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            if (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == tPID, wsAt == nil { wsAt = now() }
        }

        let t3 = now()
        activate(window: tW, pid: tPID, method: .nsRunningApp)
        // Observe raw ordering, before any of our notifications run (we poll the CG list).
        var firstWAboveF: Double? = nil, stripCoveredSamples = 0, samples = 0
        _ = spinUntil(timeout: 1.5, poll: 0.001) {
            let l = cgWindows()
            guard let iW = zIndex(tID, in: l), let iF = zIndex(fID, in: l), let iP = zIndex(pID, in: l) else { return false }
            if iW < iF {
                if firstWAboveF == nil { firstWAboveF = now() }
                samples += 1
                if iP > iF { stripCoveredSamples += 1 }
            }
            return firstWAboveF != nil && now() - firstWAboveF! > 0.3
        }
        log("3 activation → W above F after \(firstWAboveF.map { ms($0 - t3) } ?? "never"); NSWorkspace didActivate after \(wsAt.map { ms($0 - t3) } ?? "never"); first AX notif after \(notifAt.map { ms($0 - t3) } ?? "never")")
        log("3 settle burst corrections: \(burstFixes)")
        log("3 strip wrongly behind F in \(stripCoveredSamples)/\(samples) samples after W came up (window of exposure ≈ \(reorderedAt.flatMap { r in firstWAboveF.map { ms(max(0, r - $0)) } } ?? "?"))")
        check("3 after re-activation + re-order: strip above F and directly above W", idx(pID) < idx(fID) && idx(pID) == idx(tID) - 1)

        // 4. Clicking the non-activating strip must not activate us or steal focus.
        let pc = CGPoint(x: wFrame.midX, y: wFrame.minY - 14)
        let beforeFront = frontmostPID()
        DispatchQueue.global().async { postMouse(.leftMouseDown, pc); usleep(60_000); postMouse(.leftMouseUp, pc) }
        spin(0.4)
        check("4 click on strip leaves \(tApp.localizedName ?? "") frontmost (no focus steal)", frontmostPID() == beforeFront && frontmostPID() != getpid())
        check("4 click on strip keeps it directly above W", idx(pID) == idx(tID) - 1)

        // 5. Strip follows W while W moves (simulated user move through AX).
        var follow: [Double] = []
        obs?.handler = { notif, _ in
            if notif == kAXMovedNotification || notif == kAXResizedNotification, let f = axFrame(tW) {
                p.setFrame(nsRect(fromCG: stripFrame(f)), display: true)
            }
            p.order(.above, relativeTo: Int(tID))
        }
        for i in 1...10 {
            let target = CGRect(x: wFrame.minX + CGFloat(i * 12), y: wFrame.minY + CGFloat(i * 6), width: wFrame.width, height: wFrame.height)
            let t = now()
            axSetPosition(tW, target.origin)
            if let d = spinUntil(timeout: 0.5, poll: 0.001, { abs(cgRect(fromNS: p.frame).minX - target.minX) < 1 }) { follow.append(d) }
            _ = t
        }
        log("5 strip followed \(follow.count)/10 AX moves; median lag \(follow.sorted().dropFirst(follow.count / 2).first.map(ms) ?? "?")")
        check("5 strip follows W via kAXMovedNotification", follow.count == 10)

        // 6. Hide test: order out / back in relative to W.
        let tOut = now()
        p.orderOut(nil)
        let gone = spinUntil(timeout: 2, poll: 0.001) { idx(pID) == -1 }
        log("6 orderOut → gone from CG on-screen list after \(gone.map(ms) ?? "never (2 s)"); isVisible \(p.isVisible); animationBehavior \(p.animationBehavior.rawValue)")
        _ = tOut
        p.alphaValue = 0; spin(0.05)
        check("6 orderOut hides strip (or alpha 0 fallback)", idx(pID) == -1 || p.alphaValue == 0)
        p.alphaValue = 1
        p.order(.above, relativeTo: Int(tID)); spin(0.1)
        check("6 order(.above) restores strip directly above W", idx(pID) == idx(tID) - 1)

        let fol = Follow()
        if hold > 0 {
            obs?.handler = { notif, _ in
                let dragging = args.contains("--follow-mouse") && NSEvent.pressedMouseButtons & 1 == 1
                if dragging, notif == kAXMovedNotification, fol.downMouse != nil, args.contains("--ax-reanchor"), let f = axFrame(tW) {
                    // Re-anchor: real frame now ↔ mouse now. Record how far the prediction was off.
                    if fol.anchored, let m = fol.downMouse, let d = fol.downFrame {
                        let predicted = d.offsetBy(dx: fol.lastMouse.x - m.x, dy: fol.lastMouse.y - m.y)
                        fol.errs.append(hypot(predicted.minX - f.minX, predicted.minY - f.minY))
                    }
                    fol.downMouse = fol.lastMouse; fol.downFrame = f; fol.anchored = true; fol.reanchors += 1
                    p.setFrame(nsRect(fromCG: stripFrame(f)), display: true)
                } else if !dragging, let f = axFrame(tW) {
                    p.setFrame(nsRect(fromCG: stripFrame(f)), display: true)
                }
                p.order(.above, relativeTo: Int(tID)); settle()
                log("  hold: \(notif) → strip re-synced; \(order())")
            }
            // Follow the mouse during a title-bar drag of W (AX "moved" is too sparse mid-drag).
            let followMouse = args.contains("--follow-mouse")
            var followTap: CFMachPort?
            if followMouse {
                let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
                let box = Unmanaged.passRetained(ClosureBox { type, loc in
                    switch type {
                    case .leftMouseDown:
                        if let f = axFrame(tW), CGRect(x: f.minX, y: f.minY, width: f.width, height: 32).contains(loc) {
                            fol.downMouse = loc; fol.downFrame = f
                        }
                    case .leftMouseDragged:
                        fol.lastMouse = loc
                        // Until the window has actually started moving (drag threshold), hold the strip still.
                        // Strip takes the WindowServer's bounds for W on every drag event.
                        if fol.downMouse != nil {
                            var ptr = UnsafeRawPointer(bitPattern: UInt(tID))
                            let arr = CFArrayCreate(nil, &ptr, 1, nil)
                            if let d = (CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]])?.first,
                               let bd = d[kCGWindowBounds as String] as? NSDictionary, let b = CGRect(dictionaryRepresentation: bd) {
                                fol.events += 1
                                p.setFrame(nsRect(fromCG: stripFrame(b)), display: true)
                            }
                        }
                    default:
                        fol.downMouse = nil; fol.anchored = false
                        if let f = axFrame(tW) { p.setFrame(nsRect(fromCG: stripFrame(f)), display: true) }
                    }
                })
                followTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                              eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
                    Unmanaged<ClosureBox>.fromOpaque(refcon!).takeUnretainedValue().f(type, event.location)
                    return Unmanaged.passUnretained(event)
                }, userInfo: box.toOpaque())
                if let followTap {
                    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, followTap, 0), .commonModes)
                    CGEvent.tapEnable(tap: followTap, enable: true)
                }
            }
            banner("Strip test: click other apps, ⌘Tab, drag Terminal (\(Int(hold)) s)")
            log("HOLD \(Int(hold)) s: the red strip should stay glued above the \(tApp.localizedName ?? "") window and be covered by any other window placed over it. Click other apps, Cmd-Tab, drag W around.")
            spin(hold)
            bannerPanel?.orderOut(nil)
            if followMouse {
                let e = fol.errs.sorted()
                log("follow-mouse: strip moved on \(fol.events) drag events, \(fol.reanchors) re-anchors; prediction error at re-anchor median \(e.isEmpty ? "-" : f1(Double(e[e.count / 2]))) pt, p90 \(e.isEmpty ? "-" : f1(Double(e[e.count * 9 / 10]))) pt, max \(f1(Double(e.last ?? 0))) pt")
            }
            _ = followTap
        }

        NSWorkspace.shared.notificationCenter.removeObserver(wsObs)
        p.orderOut(nil)
        axSetFrame(tW, tOrig); axSetFrame(fW, fOrig)
        log("SUMMARY\n" + results.joined(separator: "\n"))
        withExtendedLifetime(obs) {}
    }
}

final class ClosureBox { let f: (CGEventType, CGPoint) -> Void; init(_ f: @escaping (CGEventType, CGPoint) -> Void) { self.f = f } }

final class Follow { var downMouse: CGPoint?; var downFrame: CGRect?; var events = 0; var lastMouse = CGPoint.zero; var errs: [CGFloat] = []; var reanchors = 0; var anchored = false }
