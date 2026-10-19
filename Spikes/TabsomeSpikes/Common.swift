// Shared helpers for the Phase 0 spikes. Throwaway code: correctness over polish.
// NOTE: spikes deliberately break product rules (AX outside AXWindow.swift, AX on the
// main thread, reading app content for metrics). Product code must not copy this.

import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Logging

let spikeStart = ProcessInfo.processInfo.systemUptime
nonisolated(unsafe) var logHandle: FileHandle?

func now() -> Double { ProcessInfo.processInfo.systemUptime }
func ms(_ seconds: Double) -> String { String(format: "%.1f ms", seconds * 1000) }
func f1(_ v: Double) -> String { String(format: "%.1f", v) }

func log(_ s: String) {
    let line = String(format: "[%7.3f] ", now() - spikeStart) + s
    print(line)
    if let h = logHandle, let d = (line + "\n").data(using: .utf8) { h.write(d) }
}

func openLog(named name: String) {
    let dir = (CommandLine.arguments.first.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: "."))
        .deletingLastPathComponent() // MacOS
        .deletingLastPathComponent() // Contents
        .deletingLastPathComponent() // .app
        .deletingLastPathComponent() // out
        .appendingPathComponent("logs")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(name).log")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    logHandle = try? FileHandle(forWritingTo: url)
    log("log file: \(url.path)")
}

// MARK: - Private symbol (plan §2)

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - AX helpers

func axCopy(_ el: AXUIElement, _ attr: String) -> (AXError, CFTypeRef?) {
    var v: CFTypeRef?
    let e = AXUIElementCopyAttributeValue(el, attr as CFString, &v)
    return (e, v)
}

func axString(_ el: AXUIElement, _ attr: String) -> String? {
    let (e, v) = axCopy(el, attr)
    guard e == .success, let v, CFGetTypeID(v) == CFStringGetTypeID() else { return nil }
    return (v as! CFString) as String
}

func axBool(_ el: AXUIElement, _ attr: String) -> Bool? {
    let (e, v) = axCopy(el, attr)
    guard e == .success, let v, CFGetTypeID(v) == CFBooleanGetTypeID() else { return nil }
    return CFBooleanGetValue((v as! CFBoolean))
}

func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    let (e, v) = axCopy(el, attr)
    guard e == .success, let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

func axElements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
    let (e, v) = axCopy(el, attr)
    guard e == .success, let arr = v as? [AnyObject] else { return [] }
    return arr.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
}

func axPoint(_ el: AXUIElement, _ attr: String = kAXPositionAttribute) -> CGPoint? {
    let (e, v) = axCopy(el, attr)
    guard e == .success, let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
}

func axSize(_ el: AXUIElement, _ attr: String = kAXSizeAttribute) -> CGSize? {
    let (e, v) = axCopy(el, attr)
    guard e == .success, let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
}

/// Frame in global top-left-origin coordinates (same space as CGWindowList bounds).
func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let p = axPoint(el), let s = axSize(el) else { return nil }
    return CGRect(origin: p, size: s)
}

@discardableResult
func axSetPosition(_ el: AXUIElement, _ p: CGPoint) -> AXError {
    var p = p
    let v = AXValueCreate(.cgPoint, &p)!
    return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
}

@discardableResult
func axSetSize(_ el: AXUIElement, _ s: CGSize) -> AXError {
    var s = s
    let v = AXValueCreate(.cgSize, &s)!
    return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
}

/// The size → position → size pattern from plan §5.4.
@discardableResult
func axSetFrame(_ el: AXUIElement, _ r: CGRect) -> [AXError] {
    [axSetSize(el, r.size), axSetPosition(el, r.origin), axSetSize(el, r.size)]
}

func axSettable(_ el: AXUIElement, _ attr: String) -> Bool {
    var b: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(el, attr as CFString, &b) == .success && b.boolValue
}

func axWindows(pid: pid_t) -> [AXUIElement] {
    axElements(AXUIElementCreateApplication(pid), kAXWindowsAttribute)
}

func windowID(_ el: AXUIElement) -> CGWindowID? {
    var wid: CGWindowID = 0
    return _AXUIElementGetWindow(el, &wid) == .success && wid != 0 ? wid : nil
}

func axStandardWindows(pid: pid_t) -> [AXUIElement] {
    axWindows(pid: pid).filter { axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
}

extension AXError {
    var name: String {
        switch self {
        case .success: "success"
        case .failure: "failure"
        case .illegalArgument: "illegalArgument"
        case .invalidUIElement: "invalidUIElement"
        case .cannotComplete: "cannotComplete"
        case .attributeUnsupported: "attributeUnsupported"
        case .actionUnsupported: "actionUnsupported"
        case .notImplemented: "notImplemented"
        case .apiDisabled: "apiDisabled"
        case .noValue: "noValue"
        case .notificationUnsupported: "notificationUnsupported"
        default: "AXError(\(rawValue))"
        }
    }
}

// MARK: - CGWindowList helpers

struct CGWin {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
    let owner: String
    let onScreen: Bool
    let alpha: Double
}

func cgWindows(onScreenOnly: Bool = true) -> [CGWin] {
    let opts: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { d in
        guard let id = d[kCGWindowNumber as String] as? CGWindowID,
              let pid = d[kCGWindowOwnerPID as String] as? pid_t,
              let layer = d[kCGWindowLayer as String] as? Int,
              let bd = d[kCGWindowBounds as String] as? NSDictionary,
              let b = CGRect(dictionaryRepresentation: bd) else { return nil }
        return CGWin(id: id, pid: pid, layer: layer, bounds: b,
                     owner: d[kCGWindowOwnerName as String] as? String ?? "?",
                     onScreen: d[kCGWindowIsOnscreen as String] as? Bool ?? false,
                     alpha: d[kCGWindowAlpha as String] as? Double ?? 1)
    }
}

/// Front-to-back index among on-screen layer-0 windows (includes our own panels at layer 0).
func zIndex(_ id: CGWindowID, in list: [CGWin]) -> Int? {
    list.filter { $0.layer == 0 }.firstIndex { $0.id == id }
}

func describeOrder(_ ids: [CGWindowID: String]) -> String {
    let list = cgWindows().filter { $0.layer == 0 }
    var out: [String] = []
    for (i, w) in list.enumerated() {
        if let name = ids[w.id] { out.append("\(i):\(name)") }
    }
    return out.joined(separator: " > ")
}

// MARK: - Coordinates

/// Height of the primary display, for converting top-left (CG/AX) <-> bottom-left (AppKit).
var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

func nsRect(fromCG r: CGRect) -> NSRect {
    NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
}

func cgRect(fromNS r: NSRect) -> CGRect {
    CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
}

// MARK: - Apps

func runningApp(_ bundleID: String) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
}

/// Wait (spinning the main run loop) until `cond` is true or timeout. Returns elapsed or nil.
@discardableResult
func spinUntil(timeout: Double, poll: Double = 0.002, _ cond: () -> Bool) -> Double? {
    let start = now()
    while now() - start < timeout {
        if cond() { return now() - start }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: poll))
    }
    return cond() ? now() - start : nil
}

func spin(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }

func frontmostPID() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

enum ActivateMethod: String, CaseIterable {
    case nsRunningApp   // NSRunningApplication.activate()
    case axFrontmost    // AXFrontmost = true on the app element
    case raiseOnly      // AXRaise only, no app activation
}

/// "Switch to tab": raise the window and (optionally) activate its app.
func activate(window: AXUIElement, pid: pid_t, method: ActivateMethod) {
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    switch method {
    case .nsRunningApp:
        NSRunningApplication(processIdentifier: pid)?.activate()
    case .axFrontmost:
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    case .raiseOnly:
        break
    }
}

// MARK: - Synthesized input (needs Accessibility)

func postMouse(_ type: CGEventType, _ p: CGPoint, clickState: Int64 = 1) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
    e?.setIntegerValueField(.mouseEventClickState, value: clickState)
    e?.post(tap: .cghidEventTap)
}

/// Press at `from`, drag in steps to `to`, release. Blocking: call off the main thread.
func synthDrag(from: CGPoint, to: CGPoint, steps: Int = 30, stepDelay: useconds_t = 12_000,
               holdBeforeRelease: useconds_t = 150_000, holdAfterDown: useconds_t = 120_000) {
    postMouse(.mouseMoved, from)
    usleep(60_000)
    postMouse(.leftMouseDown, from)
    usleep(holdAfterDown)
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        postMouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        usleep(stepDelay)
    }
    usleep(holdBeforeRelease)
    postMouse(.leftMouseUp, to)
}

func requireAX() -> Bool {
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    let ok = AXIsProcessTrustedWithOptions(opts)
    if !ok {
        log("ACCESSIBILITY NOT GRANTED. System Settings › Privacy & Security › Accessibility → enable TabsomeSpikes, then re-run.")
    }
    return ok
}

/// Simple overlay panel matching plan §5.6 settings.
func makeStripPanel(frameCG: CGRect, color: NSColor) -> NSPanel {
    let p = NSPanel(contentRect: nsRect(fromCG: frameCG),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.isFloatingPanel = false
    p.level = .normal
    p.collectionBehavior = [.managed, .fullScreenNone]
    p.hidesOnDeactivate = false
    p.hasShadow = false
    p.backgroundColor = color
    p.isReleasedWhenClosed = false
    return p
}

// MARK: - AXObserver wrapper

final class AXObs {
    let observer: AXObserver
    var handler: (String, AXUIElement) -> Void

    init?(pid: pid_t, runLoop: CFRunLoop = CFRunLoopGetCurrent(), handler: @escaping (String, AXUIElement) -> Void) {
        self.handler = handler
        var o: AXObserver?
        let err = AXObserverCreate(pid, { _, el, notif, refcon in
            guard let refcon else { return }
            let me = Unmanaged<AXObs>.fromOpaque(refcon).takeUnretainedValue()
            me.handler(notif as String, el)
        }, &o)
        guard err == .success, let o else { return nil }
        observer = o
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(o), .defaultMode)
    }

    @discardableResult
    func add(_ el: AXUIElement, _ notif: String) -> AXError {
        AXObserverAddNotification(observer, el, notif as CFString, Unmanaged.passUnretained(self).toOpaque())
    }
}

// MARK: - On-screen label for human comparisons

nonisolated(unsafe) var bannerPanel: NSPanel?
func banner(_ text: String) {
    let screen = NSScreen.screens[0].frame
    if bannerPanel == nil {
        let p = NSPanel(contentRect: NSRect(x: screen.midX - 360, y: screen.maxY - 120, width: 720, height: 56),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        p.animationBehavior = .none
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 10, y: 12, width: 700, height: 32)
        p.contentView?.addSubview(label)
        bannerPanel = p
    }
    (bannerPanel!.contentView!.subviews.first as! NSTextField).stringValue = text
    bannerPanel!.orderFrontRegardless()
    log("BANNER: \(text)")
}
