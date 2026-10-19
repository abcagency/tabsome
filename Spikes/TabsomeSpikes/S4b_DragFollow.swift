// Spike 4b: how does a dragged window's real position track the cursor? Decides how the strip
// follows a live drag. Synthesizes a title-bar drag of Terminal and samples, per mouse event:
// cursor, WindowServer bounds (single-window CGWindowList query) and the AX frame.

import AppKit

enum S4b {
    struct Sample { let t: Double; let mouse: CGPoint; let cg: CGRect?; let ax: CGRect?; let cgCost: Double }

    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        let bid = args.first ?? "com.apple.Terminal"
        guard let app = runningApp(bid), let w = axStandardWindows(pid: app.processIdentifier).first, let wid = windowID(w) else { log("no window for \(bid)"); return }
        let orig = axFrame(w)!
        axSetFrame(w, CGRect(x: 300, y: 260, width: 760, height: 420))
        activate(window: w, pid: app.processIdentifier, method: .nsRunningApp)
        spin(0.5)
        let f = axFrame(w)!

        var samples: [Sample] = []
        var downMouse: CGPoint?
        func cgBounds() -> (CGRect?, Double) {
            let t = now()
            var ptr = UnsafeRawPointer(bitPattern: UInt(wid))
            let arr = CFArrayCreate(nil, &ptr, 1, nil)
            let desc = CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]]
            let b = (desc?.first?[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
            return (b, now() - t)
        }
        let box = Unmanaged.passRetained(ClosureBox { type, loc in
            if type == .leftMouseDown { downMouse = loc }
            if type == .leftMouseDragged || type == .leftMouseUp {
                let (b, c) = cgBounds()
                samples.append(Sample(t: now(), mouse: loc, cg: b, ax: axFrame(w), cgCost: c))
            }
        })
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            Unmanaged<ClosureBox>.fromOpaque(refcon!).takeUnretainedValue().f(type, event.location)
            return Unmanaged.passUnretained(event)
        }, userInfo: box.toOpaque())!
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        for (label, steps, delay) in [("slow", 80, useconds_t(16_000)), ("fast", 25, useconds_t(8_000))] {
            samples = []
            axSetFrame(w, f); spin(0.4)
            let a = CGPoint(x: f.midX + 60, y: f.minY + 12), b = CGPoint(x: f.midX + 360, y: f.minY + 172)
            var done = false
            DispatchQueue.global().async { synthDrag(from: a, to: b, steps: steps, stepDelay: delay, holdBeforeRelease: 200_000); done = true }
            spinUntil(timeout: 6) { done }
            spin(0.3)
            guard let m0 = downMouse, !samples.isEmpty else { log("\(label): no samples"); continue }
            // Expected position if the window followed the cursor 1:1 from mouse-down.
            func predicted(_ m: CGPoint) -> CGPoint { CGPoint(x: f.minX + m.x - m0.x, y: f.minY + m.y - m0.y) }
            let firstMove = samples.firstIndex { ($0.cg?.minX ?? f.minX) != f.minX || ($0.cg?.minY ?? f.minY) != f.minY }
            let thresh = firstMove.map { hypot(samples[$0].mouse.x - m0.x, samples[$0].mouse.y - m0.y) }
            let cgErr = samples.compactMap { s in s.cg.map { hypot($0.minX - predicted(s.mouse).x, $0.minY - predicted(s.mouse).y) } }.sorted()
            let axErr = samples.compactMap { s in s.ax.map { hypot($0.minX - predicted(s.mouse).x, $0.minY - predicted(s.mouse).y) } }.sorted()
            // Constant offset? Compare cursor→window offset at the end vs start of the drag.
            let offEnd = samples.last.flatMap { s in s.cg.map { CGPoint(x: $0.minX - s.mouse.x, y: $0.minY - s.mouse.y) } }
            let offStart = CGPoint(x: f.minX - m0.x, y: f.minY - m0.y)
            let finalCG = samples.last?.cg
            let cost = samples.map(\.cgCost).sorted()
            func q(_ a: [CGFloat], _ p: Double) -> String { a.isEmpty ? "-" : f1(Double(a[min(a.count - 1, Int(Double(a.count) * p))])) }
            log("\(label) (\(samples.count) events): window starts moving after cursor travels \(thresh.map { f1(Double($0)) } ?? "?") pt")
            log("  WindowServer bounds vs 1:1 cursor: median \(q(cgErr, 0.5)) pt, p90 \(q(cgErr, 0.9)), max \(q(cgErr, 1))")
            log("  AX frame vs 1:1 cursor:            median \(q(axErr, 0.5)) pt, p90 \(q(axErr, 0.9)), max \(q(axErr, 1))")
            log("  cursor→window offset start \(Int(offStart.x)),\(Int(offStart.y)) end \(offEnd.map { "\(Int($0.x)),\(Int($0.y))" } ?? "?"); final CG \(finalCG.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "?") vs 1:1 \(Int(predicted(b).x)),\(Int(predicted(b).y))")
            log("  single-window CG query cost median \(ms(cost[cost.count / 2])), max \(ms(cost.last!))")
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        axSetFrame(w, orig)
    }
}
