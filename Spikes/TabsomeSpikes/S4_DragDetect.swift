// Spike 4: title-bar drag detection (plan §5.1) without false positives from text selection
// or resizing.
//
//   drag-detect           automated gestures on Terminal and Finder (don't touch the mouse)
//   drag-detect manual 90 live classification of the human's gestures for 90 s

import AppKit

final class DragDetector {
    enum Kind: String { case none = "NONE", drag = "DRAG", resize = "RESIZE" }

    var down = false
    var downAt = 0.0, firstDraggedAt: Double?, firstMoveAt: Double?
    var downWindow: CGWindowID?
    var downApp = "", downSize: CGSize?
    var kind = Kind.none
    var movedCount = 0, resizedCount = 0, movedWhileDown = 0
    var observers: [pid_t: AXObs] = [:]
    var monitor: Any?
    var onGesture: ((Kind, String) -> Void)?
    var stripFollower: ((CGWindowID) -> Void)?

    var useTap = false
    var monitorEvents = 0, tapEvents = 0
    var tap: CFMachPort?

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in
            guard let self else { return }
            self.monitorEvents += 1
            if !self.useTap {
                let p = NSEvent.mouseLocation
                self.handle(e.type, CGPoint(x: p.x, y: primaryHeight - p.y))
            }
        }
        // Listen-only event tap for mouse buttons/drags (no keyboard → no Input Monitoring).
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            let me = Unmanaged<DragDetector>.fromOpaque(refcon!).takeUnretainedValue()
            me.tapEvents += 1
            if me.useTap {
                let t: NSEvent.EventType = type == .leftMouseDown ? .leftMouseDown : type == .leftMouseUp ? .leftMouseUp : .leftMouseDragged
                let loc = event.location
                DispatchQueue.main.async { me.handle(t, loc) }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else { log("CGEvent tap creation FAILED") }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            observe(app.processIdentifier)
        }
    }

    func observe(_ pid: pid_t) {
        guard observers[pid] == nil, let o = AXObs(pid: pid, handler: { [weak self] n, el in self?.axEvent(n, el) }) else { return }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.5)
        o.add(appEl, kAXWindowMovedNotification)
        o.add(appEl, kAXWindowResizedNotification)
        observers[pid] = o
    }

    func handle(_ type: NSEvent.EventType, _ cgP: CGPoint) {
        switch type {
        case .leftMouseDown:
            down = true; downAt = now(); firstDraggedAt = nil; firstMoveAt = nil
            kind = .none; movedCount = 0; resizedCount = 0; movedWhileDown = 0
            let hit = cgWindows().first { $0.layer == 0 && $0.pid != getpid() && $0.bounds.contains(cgP) }
            downWindow = hit?.id
            downApp = hit?.owner ?? "?"
            downSize = nil
            if let hit {
                observe(hit.pid)
                if let w = axWindows(pid: hit.pid).first(where: { windowID($0) == hit.id }) { downSize = axSize(w) }
            }
        case .leftMouseDragged:
            if firstDraggedAt == nil { firstDraggedAt = now() }
        case .leftMouseUp:
            guard down else { return }
            down = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.report() } // trailing AX notifications
        default: break
        }
    }

    func report() {
            let lat = (firstMoveAt != nil && firstDraggedAt != nil) ? ms(firstMoveAt! - firstDraggedAt!) : "-"
            let detail = "\(downApp): \(kind.rawValue) (moved notifs while down \(movedWhileDown), total moved \(movedCount), resized \(resizedCount), first-move latency \(lat))"
            log("gesture → \(detail)")
            onGesture?(kind, detail)
    }

    func axEvent(_ n: String, _ el: AXUIElement) {
        guard let id = windowID(el), id == downWindow else { return }
        if n == kAXWindowMovedNotification {
            movedCount += 1
            if down { movedWhileDown += 1 }
            if down, kind == .none {
                // A move is a title-bar drag only if the size is unchanged; resizing from the
                // top or left edge also fires "moved".
                let sizeNow = axSize(el)
                if let s0 = downSize, let s1 = sizeNow, abs(s0.width - s1.width) < 1, abs(s0.height - s1.height) < 1 {
                    kind = .drag; firstMoveAt = now()
                } else {
                    kind = .resize
                }
            }
            if kind == .drag { stripFollower?(id) }
        } else if n == kAXWindowResizedNotification {
            resizedCount += 1
            if down { kind = .resize }
        }
    }
}

enum S4 {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        let det = DragDetector()
        det.useTap = args.contains("--tap")
        det.start()
        log("event source: \(det.useTap ? "CGEventTap (listen-only)" : "NSEvent global monitor")")

        if args.first == "manual" {
            let secs = Double(args.dropFirst().first ?? "90") ?? 90
            log("MANUAL \(Int(secs)) s: drag windows by the title bar, select text, resize from every edge/corner, click title bars, scroll. Each gesture is classified below.")
            // Don't block: NSEvent monitors are delivered through NSApp's event loop, which a
            // nested RunLoop spin doesn't service.
            keepAlive = true
            Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { _ in
                log("events seen: NSEvent monitor \(det.monitorEvents), CGEventTap \(det.tapEvents)")
                withExtendedLifetime(det) {}
                finish()
            }
            return
        }

        var results: [String] = []
        for bid in ["com.apple.Terminal", "com.apple.finder"] {
            guard let app = runningApp(bid), let w = axStandardWindows(pid: app.processIdentifier).first else { log("skip \(bid): no window"); continue }
            let orig = axFrame(w)!
            axSetFrame(w, CGRect(x: 300, y: 260, width: 760, height: 420))
            activate(window: w, pid: app.processIdentifier, method: .nsRunningApp)
            spin(0.5)
            let f = axFrame(w)! // actual (Terminal snaps to its character grid)
            let name = app.localizedName ?? bid

            let gestures: [(String, DragDetector.Kind, CGPoint, CGPoint)] = [
                ("title-bar drag", .drag, CGPoint(x: f.midX + 60, y: f.minY + 12), CGPoint(x: f.midX + 260, y: f.minY + 112)),
                ("content drag (text/rubber-band selection)", .none, CGPoint(x: f.minX + 120, y: f.minY + 200), CGPoint(x: f.minX + 420, y: f.minY + 320)),
                ("resize bottom-right corner", .resize, CGPoint(x: f.maxX - 2, y: f.maxY - 2), CGPoint(x: f.maxX + 80, y: f.maxY + 60)),
                ("resize top-left corner (also moves origin)", .resize, CGPoint(x: f.minX + 2, y: f.minY + 2), CGPoint(x: f.minX - 60, y: f.minY - 40)),
                ("resize left edge (also moves origin)", .resize, CGPoint(x: f.minX + 1, y: f.midY), CGPoint(x: f.minX - 70, y: f.midY)),
                ("click title bar, no move", .none, CGPoint(x: f.midX + 60, y: f.minY + 12), CGPoint(x: f.midX + 60, y: f.minY + 12)),
            ]
            for (label, expect, a, b) in gestures {
                axSetFrame(w, f); spin(0.35)
                var got: DragDetector.Kind?
                var detail = ""
                det.onGesture = { k, d in got = k; detail = d }
                DispatchQueue.global().async { synthDrag(from: a, to: b) }
                spinUntil(timeout: 3) { got != nil }
                let ok = got == expect
                log("  events so far: monitor \(det.monitorEvents), tap \(det.tapEvents); window now \(axFrame(w).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "?")")
                let line = "\(ok ? "PASS" : "FAIL") \(name) — \(label): expected \(expect.rawValue), got \(got?.rawValue ?? "nothing") [\(detail)]"
                log(line); results.append(line)
            }
            axSetFrame(w, orig)
        }
        log("SUMMARY\n" + results.joined(separator: "\n"))
    }
}
