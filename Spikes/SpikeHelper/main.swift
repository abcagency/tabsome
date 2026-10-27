// SpikeHelper: a cooperative test app for the spikes.
//   role "main" (default): a window that can hang its main thread on request (spike 7)
//                          and a drag source that drags a file (spike 9)
//   role "sink":           two stacked windows; the lower one ("SINK") accepts file drops (spike 9)
//   role "quiet":          one small window, never activates (the Phase 5d leak test, launched hidden)
//   role "badge":          one window and a Dock badge; post com.tabsome.spikehelper.badge with the
//                          text as the object to change it ("" clears it) (Phase 6b)
// Controlled by distributed notifications so the spike app needs no extra permissions.

import AppKit

setvbuf(stdout, nil, _IONBF, 0)
let role = CommandLine.arguments.dropFirst().first ?? "main"

func logsDir() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("logs")
}
func hlog(_ s: String) {
    let line = String(format: "[helper-%@ %.3f] %@", role, ProcessInfo.processInfo.systemUptime, s)
    print(line)
    let url = logsDir().appendingPathComponent("helper-\(role).log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close() }
    else { try? (line + "\n").write(to: url, atomically: true, encoding: .utf8) }
}

let primaryH = NSScreen.screens[0].frame.height
func nsRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: primaryH - y - h, width: w, height: h) }

func makeWindow(_ title: String, _ r: NSRect, color: NSColor) -> NSWindow {
    let w = NSWindow(contentRect: r, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    w.title = title
    w.isReleasedWhenClosed = false
    w.tabbingMode = .disallowed // the user's "prefer tabs" setting would merge the helper windows
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 28, weight: .bold)
    label.frame = NSRect(x: 20, y: 20, width: r.width - 40, height: 40)
    let v = NSView(frame: NSRect(origin: .zero, size: r.size))
    v.wantsLayer = true
    v.layer?.backgroundColor = color.cgColor
    v.addSubview(label)
    w.contentView = v
    return w
}

final class DragSourceView: NSView, NSDraggingSource {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { hlog("source mouseDown") }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        dragging = true
        let file = logsDir().appendingPathComponent("spike-drop.txt")
        try? "dropped by spike 9\n".write(to: file, atomically: true, encoding: .utf8)
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(bounds.insetBy(dx: 30, dy: 30), contents: NSImage(systemSymbolName: "doc", accessibilityDescription: nil))
        hlog("beginDraggingSession with \(file.lastPathComponent)")
        beginDraggingSession(with: [item], event: event, source: self)
    }
    var dragging = false
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        dragging = false
        hlog("drag ended operation=\(operation.rawValue)")
    }
}

final class SinkView: NSView {
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { hlog("sink draggingEntered"); return .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        hlog("SINK RECEIVED DROP: \(urls.map(\.lastPathComponent))")
        DistributedNotificationCenter.default().postNotificationName(.init("com.tabsome.spike.dropped"), object: urls.first?.lastPathComponent, userInfo: nil, deliverImmediately: true)
        return true
    }
}

final class HelperDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ n: Notification) {
        if role == "badge" {
            let w = makeWindow("BADGE", nsRect(160, 200, 640, 400), color: .systemRed.withAlphaComponent(0.25))
            w.orderFront(nil)
            windows = [w]
            NSApp.dockTile.badgeLabel = "3"
            DistributedNotificationCenter.default().addObserver(forName: .init("com.tabsome.spikehelper.badge"), object: nil, queue: .main) { n in
                let text = n.object as? String ?? ""
                NSApp.dockTile.badgeLabel = text.isEmpty ? nil : text
                hlog("badge \(text.isEmpty ? "cleared" : text)")
            }
            return hlog("ready pid \(getpid())")
        }
        if role == "quiet" {
            let w = makeWindow("LEAK TEST", nsRect(40, 600, 220, 140), color: .systemGray.withAlphaComponent(0.3))
            w.orderFront(nil)
            windows = [w]
            return hlog("ready pid \(getpid())")
        }
        if role == "sink" {
            let sink = makeWindow("SINK (background tab)", nsRect(420, 320, 640, 400), color: .systemGreen.withAlphaComponent(0.4))
            let sv = SinkView(frame: sink.contentView!.bounds); sv.autoresizingMask = [.width, .height]
            sink.contentView!.addSubview(sv)
            let decoy = makeWindow("DECOY (active tab)", nsRect(420, 320, 640, 400), color: .systemOrange.withAlphaComponent(0.4))
            sink.orderFront(nil); decoy.orderFront(nil)
            windows = [sink, decoy]
        } else {
            let w = makeWindow("HELPER (hang target)", nsRect(1100, 160, 420, 260), color: .systemPurple.withAlphaComponent(0.3))
            let src = makeWindow("DRAG SOURCE", nsRect(80, 120, 260, 200), color: .systemBlue.withAlphaComponent(0.3))
            let dv = DragSourceView(frame: src.contentView!.bounds); dv.autoresizingMask = [.width, .height]
            src.contentView!.addSubview(dv)
            w.orderFront(nil); src.orderFront(nil)
            windows = [w, src]
            DistributedNotificationCenter.default().addObserver(forName: .init("com.tabsome.spike.hang"), object: nil, queue: .main) { n in
                let secs = Double(n.object as? String ?? "10") ?? 10
                hlog("HANGING main thread for \(secs) s")
                Thread.sleep(forTimeInterval: secs)
                hlog("hang over")
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.tabsome.spike.quit-helpers"), object: nil, queue: .main) { _ in exit(0) }
        NSApp.activate()
        hlog("ready pid \(getpid())")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let d = HelperDelegate()
app.delegate = d
app.run()
