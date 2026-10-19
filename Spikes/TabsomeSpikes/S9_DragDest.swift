// Spike 9: cross-app drag destination on a non-activating panel (plan §5.14).
// The strip panel registers for many drag types, never accepts the drop, and spring-loads:
// hovering 0.5 s raises the "background tab". The drop must still land in the window below.
//
//   drag-dest            automated with SpikeHelper (source = helper "main", sink = helper "sink")
//   drag-dest manual 60  panel at the top of the screen for 60 s; drag a file from Finder over it

import AppKit

final class SpringDropView: NSView {
    var entered = 0, updated = 0, exited = 0, performed = 0
    var hoverStart: Double?
    var springDelay = 0.5
    var onSpring: (() -> Void)?
    var fired = false
    var flash: NSColor = .systemTeal

    static let types: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .tiff, .png, .pdf, .rtf, .rtfd, .html, .color, .sound, .multipleTextSelection, .tabularText,
        NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        NSPasteboard.PasteboardType("public.data"), NSPasteboard.PasteboardType("public.item"),
        NSPasteboard.PasteboardType("public.content"), NSPasteboard.PasteboardType("public.image"),
    ] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(Self.types)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemIndigo.withAlphaComponent(0.85).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        entered += 1; hoverStart = now(); fired = false
        log("draggingEntered (types: \(s.draggingPasteboard.types?.prefix(4).map(\.rawValue) ?? []), source app is other process: \(s.draggingSource == nil))")
        return []
    }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        updated += 1
        if !fired, let h = hoverStart, now() - h >= springDelay {
            fired = true
            log("spring-load fired after \(ms(now() - h)) → switching tab")
            layer?.backgroundColor = flash.cgColor
            onSpring?()
        }
        return [] // never accept: the item must land in the app window
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func draggingExited(_ s: NSDraggingInfo?) { exited += 1; hoverStart = nil; log("draggingExited") }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool { false }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { performed += 1; log("performDragOperation (should never happen)"); return false }
}

enum S9 {
    static func run(_ args: ArraySlice<String>) {
        if args.first == "manual" {
            let secs = Double(args.dropFirst().first ?? "60") ?? 60
            let screen = NSScreen.screens[0].frame
            let p = makeStripPanel(frameCG: CGRect(x: screen.midX - 300, y: 120, width: 600, height: 36), color: .clear)
            p.level = .floating
            let v = SpringDropView(frame: NSRect(x: 0, y: 0, width: 600, height: 36))
            v.onSpring = { log("  (in the product this would switch tabs now)") }
            p.contentView = v
            p.orderFrontRegardless()
            log("MANUAL \(Int(secs)) s: an indigo bar is near the top of the screen. Drag a file from Finder over it and hold ~0.5 s (it turns teal), then keep dragging and drop it into a window below (e.g. a TextEdit document or a Finder folder). The drop should land there, not bounce back.")
            spin(secs)
            log("entered \(v.entered), updated \(v.updated), exited \(v.exited), performed \(v.performed)")
            return
        }

        guard requireAX() else { return }
        let helpers = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tabsome.spikehelper")
        func win(_ prefix: String) -> (AXUIElement, pid_t)? {
            for h in helpers { if let w = axStandardWindows(pid: h.processIdentifier).first(where: { axString($0, kAXTitleAttribute)?.hasPrefix(prefix) == true }) { return (w, h.processIdentifier) } }
            return nil
        }
        guard let (src, srcPID) = win("DRAG SOURCE"), let (sink, sinkPID) = win("SINK"), let (decoy, _) = win("DECOY"),
              let sinkID = windowID(sink), let decoyID = windowID(decoy) else { log("need SpikeHelper main + sink roles running"); return }
        let sf = axFrame(src)!, kf = axFrame(sink)!
        // Bring the source window above whatever covers it, then the sink app above that.
        activate(window: src, pid: srcPID, method: .nsRunningApp)
        spinUntil(timeout: 1.5) { frontmostPID() == srcPID }
        spin(0.2)
        // DECOY (active tab) on top of SINK (background tab), identical frames.
        axSetFrame(decoy, kf)
        AXUIElementPerformAction(sink, kAXRaiseAction as CFString)
        AXUIElementPerformAction(decoy, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: sinkPID)?.activate()
        spin(0.4)

        let stripCG = CGRect(x: kf.minX, y: kf.minY - 32, width: kf.width, height: 32)
        let p = makeStripPanel(frameCG: stripCG, color: .clear)
        let v = SpringDropView(frame: NSRect(origin: .zero, size: stripCG.size))
        p.contentView = v
        p.order(.above, relativeTo: Int(decoyID))
        var springRaised = false
        v.onSpring = {
            AXUIElementPerformAction(sink, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(sink, kAXMainAttribute as CFString, kCFBooleanTrue)
            p.order(.above, relativeTo: Int(sinkID))
            springRaised = true
        }
        var dropped: String?
        let obs = DistributedNotificationCenter.default().addObserver(forName: .init("com.tabsome.spike.dropped"), object: nil, queue: .main) { n in
            dropped = n.object as? String ?? "?"
        }
        spin(0.3)
        log("front order before drag: \(describeOrder([CGWindowID(p.windowNumber): "STRIP", sinkID: "SINK", decoyID: "DECOY", windowID(src) ?? 0: "SOURCE"]))")

        let from = CGPoint(x: sf.midX, y: sf.midY + 20)
        let overStrip = CGPoint(x: stripCG.minX + 120, y: stripCG.midY)
        let into = CGPoint(x: kf.midX, y: kf.midY + 40)
        DispatchQueue.global().async {
            postMouse(.mouseMoved, from); usleep(80_000)
            postMouse(.leftMouseDown, from); usleep(150_000)
            func drag(_ a: CGPoint, _ b: CGPoint, _ steps: Int) {
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    postMouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)); usleep(15_000)
                }
            }
            drag(from, overStrip, 40)
            for i in 0..<40 { postMouse(.leftMouseDragged, CGPoint(x: overStrip.x + CGFloat(i % 2) * 2, y: overStrip.y)); usleep(25_000) } // hover ~1 s
            drag(overStrip, into, 30)
            usleep(250_000)
            postMouse(.leftMouseUp, into)
        }
        spinUntil(timeout: 8) { dropped != nil }
        spin(0.3)
        let topAtEnd = cgWindows().filter { $0.layer == 0 && ($0.id == sinkID || $0.id == decoyID) }.first?.id
        log("entered \(v.entered), updated \(v.updated), exited \(v.exited), performed \(v.performed), spring raised SINK \(springRaised), top window now \(topAtEnd == sinkID ? "SINK" : topAtEnd == decoyID ? "DECOY" : "?")")
        log("\(v.entered > 0 ? "PASS" : "FAIL") non-activating panel of a background app receives draggingEntered from another app")
        log("\(springRaised && topAtEnd == sinkID ? "PASS" : "FAIL") spring-load switched the background tab to the front mid-drag")
        log("\(dropped != nil && v.performed == 0 ? "PASS" : "FAIL") declined by the strip; drop landed in SINK (\(dropped ?? "nothing"))")
        DistributedNotificationCenter.default().removeObserver(obs)
        p.orderOut(nil)
    }
}
