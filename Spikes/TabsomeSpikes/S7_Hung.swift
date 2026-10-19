// Spike 7: hung-app isolation (plan §6.2 P1). SpikeHelper blocks its main thread for 10 s.
// With one AX thread per app and a 0.5 s messaging timeout, the main thread and every other
// app's AX work must keep running.

import AppKit

final class AXWorker: Thread {
    private var rl: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    let label: String
    init(_ label: String) { self.label = label; super.init(); name = "ax.\(label)" }
    override func main() {
        rl = CFRunLoopGetCurrent()
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled { CFRunLoopRunInMode(.defaultMode, 0.25, false) }
    }
    func begin() { start(); ready.wait() }
    var runLoop: CFRunLoop { rl! }
    func async(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
    }
}

final class Stats: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var samples: [(t: Double, dur: Double, err: AXError)] = []
    func add(_ t: Double, _ d: Double, _ e: AXError) { lock.lock(); samples.append((t, d, e)); lock.unlock() }
    func snapshot() -> [(t: Double, dur: Double, err: AXError)] { lock.lock(); defer { lock.unlock() }; return samples }
}

enum S7 {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        let helperMatch = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tabsome.spikehelper").lazy.compactMap { h in
            axStandardWindows(pid: h.processIdentifier).first(where: { axString($0, kAXTitleAttribute)?.hasPrefix("HELPER") == true }).map { (h, $0) }
        }.first
        guard let (helper, hW) = helperMatch,
              let term = runningApp("com.apple.Terminal"), let tW = axStandardWindows(pid: term.processIdentifier).first
        else { log("need SpikeHelper (main role) and a Terminal window running"); return }
        let finder = runningApp("com.apple.finder")
        let fW = finder.flatMap { axStandardWindows(pid: $0.processIdentifier).first }

        // Per-app workers with 0.5 s timeouts.
        let workers = ["helper": AXWorker("helper"), "terminal": AXWorker("terminal"), "finder": AXWorker("finder")]
        workers.values.forEach { $0.begin() }
        let stats = ["helper": Stats(), "terminal": Stats(), "finder": Stats()]
        for (el, pid) in [(hW, helper.processIdentifier), (tW, term.processIdentifier)] {
            AXUIElementSetMessagingTimeout(el, 0.5); AXUIElementSetMessagingTimeout(AXUIElementCreateApplication(pid), 0.5)
        }
        if let fW { AXUIElementSetMessagingTimeout(fW, 0.5) }

        // Helper worker observes notifications on its own run loop (an observer per app thread).
        nonisolated(unsafe) var helperObs: AXObs?
        nonisolated(unsafe) var helperNotifs = 0
        workers["helper"]!.async {
            helperObs = AXObs(pid: helper.processIdentifier, runLoop: workers["helper"]!.runLoop) { _, _ in helperNotifs += 1 }
            helperObs?.add(hW, kAXMovedNotification)
        }

        // Each worker loops: helper reads its frame (with unresponsive back-off), terminal and
        // finder move their window by ±1 pt and read it back.
        let stop = ManagedFlag()
        nonisolated(unsafe) var unresponsiveSince: Double? = nil, recoveredAt: Double? = nil
        func loop(_ key: String, _ body: @escaping () -> (Double, AXError), interval: Double) {
            let w = workers[key]!
            func tick() {
                guard !stop.value else { return }
                let t = now()
                let (d, e) = body()
                stats[key]!.add(t, d, e)
                var next = interval
                if key == "helper" {
                    if e == .cannotComplete {
                        if unresponsiveSince == nil { unresponsiveSince = now() }
                        next = 1.0 // back off: one probe per second while unresponsive
                    } else if unresponsiveSince != nil, recoveredAt == nil, e == .success {
                        recoveredAt = now()
                    }
                }
                w.async { usleep(useconds_t(next * 1e6)); tick() }
            }
            w.async(tick)
        }
        loop("helper", { let t = now(); let (e, _) = axCopy(hW, kAXPositionAttribute); return (now() - t, e) }, interval: 0.1)
        nonisolated(unsafe) var flip: CGFloat = 1
        let tOrig = axFrame(tW)!
        loop("terminal", {
            let t = now(); flip = -flip
            let e = axSetPosition(tW, CGPoint(x: tOrig.minX + flip, y: tOrig.minY)); _ = axFrame(tW)
            return (now() - t, e)
        }, interval: 0.1)
        if let fW {
            let fOrig = axFrame(fW)!
            nonisolated(unsafe) var ff: CGFloat = 1
            loop("finder", { let t = now(); ff = -ff; let e = axSetPosition(fW, CGPoint(x: fOrig.minX + ff, y: fOrig.minY)); return (now() - t, e) }, interval: 0.1)
        }

        // Main-thread heartbeat.
        var lastBeat = now(), maxGap = 0.0
        let beat = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            let n = now(); maxGap = max(maxGap, n - lastBeat); lastBeat = n
        }

        spin(1.0)
        let hangStart = now()
        DistributedNotificationCenter.default().postNotificationName(.init("com.tabsome.spike.hang"), object: "10", userInfo: nil, deliverImmediately: true)
        log("posted hang (10 s) to SpikeHelper; running isolated workers for 13 s")
        spin(13)
        stop.value = true
        beat.invalidate()
        spin(0.6)

        let hangEnd = hangStart + 10
        for key in ["helper", "terminal", "finder"] {
            let s = stats[key]!.snapshot()
            guard !s.isEmpty else { continue }
            let during = s.filter { $0.t >= hangStart && $0.t <= hangEnd }
            let errs = Dictionary(grouping: during, by: { $0.err.name }).mapValues(\.count)
            let maxDur = during.map(\.dur).max() ?? 0
            let ops = during.count
            log("\(key): \(ops) ops during the hang, max op \(ms(maxDur)), results \(errs)")
        }
        log("helper marked unresponsive \(unresponsiveSince.map { ms($0 - hangStart) } ?? "never") after hang start; recovered \(recoveredAt.map { ms($0 - hangEnd) } ?? "never") after hang end; helper AX notifications received \(helperNotifs)")
        log("main thread max heartbeat gap during isolated run: \(ms(maxGap))")
        let iso = maxGap < 0.1 && (stats["terminal"]!.snapshot().filter { $0.t >= hangStart && $0.t <= hangEnd }.map(\.dur).max() ?? 1) < 0.1
        log("\(iso ? "PASS" : "FAIL") isolated: main thread and Terminal stayed responsive during the hang")

        // Control: the naive approach, AX on the main thread with the default timeout.
        spin(1.0)
        DistributedNotificationCenter.default().postNotificationName(.init("com.tabsome.spike.hang"), object: "8", userInfo: nil, deliverImmediately: true)
        spin(0.5)
        let naive = AXUIElementCreateApplication(helper.processIdentifier)
        let t = now()
        let (e, _) = axCopy(naive, kAXFocusedWindowAttribute)
        log("CONTROL naive main-thread AX call with default timeout blocked main for \(ms(now() - t)) (\(e.name))")
        workers.values.forEach { $0.cancel() }
        axSetPosition(tW, tOrig.origin)
        spin(8)
    }
}

final class ManagedFlag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    var value: Bool { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}
