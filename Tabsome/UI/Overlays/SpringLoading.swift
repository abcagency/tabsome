import AppKit

/// Spring-loaded tabs (PLAN.md §5.14): dragging a file, text, or anything else over a background
/// tab switches to it after the system's spring-loading delay, so the item can be dropped into
/// that window. The tab blinks once just before it switches, like Finder's folders. Pure, so the
/// timing is tested without a drag session.
nonisolated struct SpringLoader {
    enum Effect: Equatable {
        case blink(CGWindowID)
        case endBlink
        case activate(CGWindowID)
    }

    /// How long the blink shows before the switch.
    static let blinkDuration: TimeInterval = 0.15

    var enabled: Bool
    var delay: TimeInterval
    private var target: CGWindowID?
    private var since: TimeInterval = 0
    private var blinking = false
    private var fired = false

    init(enabled: Bool, delay: TimeInterval) {
        self.enabled = enabled
        self.delay = delay
    }

    /// The system's setting: System Settings › Accessibility › Pointer Control › Spring-loading.
    static func system() -> SpringLoader {
        let d = UserDefaults.standard
        return SpringLoader(enabled: d.object(forKey: "com.apple.springing.enabled") as? Bool ?? true,
                            delay: d.object(forKey: "com.apple.springing.delay") as? Double ?? 0.5)
    }

    /// Called for every drag update. `tab` is the background tab under the item; nil over the
    /// active tab or anywhere else on the strip.
    mutating func update(tab: CGWindowID?, now: TimeInterval) -> Effect? {
        guard enabled else { return nil }
        if tab != target {
            let wasBlinking = blinking
            target = tab
            since = now
            blinking = false
            fired = false
            return wasBlinking ? .endBlink : nil
        }
        guard let tab, !fired else { return nil }
        let elapsed = now - since
        if elapsed >= delay {
            fired = true
            blinking = false
            return .activate(tab)
        }
        if !blinking, elapsed >= max(0, delay - Self.blinkDuration) {
            blinking = true
            return .blink(tab)
        }
        return nil
    }

    /// The drag left the strip or ended.
    mutating func reset() -> Effect? {
        defer { target = nil; blinking = false; fired = false }
        return blinking ? .endBlink : nil
    }
}

extension NSPasteboard.PasteboardType {
    /// Everything a drag can carry (Phase 0 spike 9), so any drag from any app reaches the strip.
    static let springLoadingTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .tiff, .png, .pdf, .rtf, .rtfd, .html, .color, .sound, .multipleTextSelection, .tabularText,
        .init("com.apple.NSFilePromiseItemMetaData"), .init("com.apple.pasteboard.promised-file-url"),
        .init("public.data"), .init("public.item"), .init("public.content"), .init("public.image"),
    ] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) }
}
