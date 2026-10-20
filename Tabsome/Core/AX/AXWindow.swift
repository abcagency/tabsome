import ApplicationServices
import CoreGraphics
import Foundation

// One of the only two files allowed to call Accessibility APIs (PLAN.md §6.1 S1, enforced by
// scripts/check-ax-usage.sh). It touches window-level attributes only: frame, title, subrole,
// minimized, full screen, main, the close button, and raise. Never an app's content.
//
// Every method runs on the owning AXApp's thread, never the main thread (PLAN.md §6.2 P1).

/// Maps an AX window to its CGWindowID. Private but widely used (Rectangle, AltTab, AeroSpace);
/// isolated here so a fallback (pid + frame + title matching) can replace it (PLAN.md §8).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

/// The per-window notifications Tabsome needs.
let axWindowNotifications: [String] = [
    kAXUIElementDestroyedNotification,
    kAXMovedNotification,
    kAXResizedNotification,
    kAXTitleChangedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
]

nonisolated final class AXWindow {
    let element: AXUIElement
    let id: CGWindowID
    let pid: pid_t

    /// Fails for elements that aren't real windows (for example Finder's desktop).
    init?(element: AXUIElement, pid: pid_t) {
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &wid) == .success, wid != 0 else { return nil }
        self.element = element
        self.id = wid
        self.pid = pid
    }

    enum ReadError: Error { case timedOut, apiDisabled, gone }

    func snapshot() -> Result<WindowSnapshot, ReadError> {
        let position: CGPoint?, size: CGSize?
        switch readPoint(kAXPositionAttribute) {
        case .success(let p): position = p
        case .failure(let e): return .failure(e)
        }
        size = (try? readSize(kAXSizeAttribute).get()) ?? nil
        let subrole = string(kAXSubroleAttribute)
        let frame = CGRect(origin: position ?? .zero, size: size ?? .zero)
        return .success(WindowSnapshot(
            id: id, pid: pid,
            title: string(kAXTitleAttribute),
            frame: frame,
            subrole: subrole,
            isStandard: subrole == kAXStandardWindowSubrole,
            isMinimized: bool(kAXMinimizedAttribute) ?? false,
            isFullScreen: bool("AXFullScreen") ?? false,
            isMain: bool(kAXMainAttribute) ?? false))
    }

    // MARK: Writes (used from Phase 3 on)

    /// The size → position → size pattern (PLAN.md §5.4).
    @discardableResult
    func setFrame(_ frame: CGRect) -> Bool {
        let a = setSize(frame.size), b = setPosition(frame.origin), c = setSize(frame.size)
        return a && b && c
    }

    @discardableResult
    func raise() -> Bool {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    }

    /// Presses the window's own close button, so the app can ask to save (PLAN.md §5.7).
    @discardableResult
    func pressClose() -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString) == .success
    }

    @discardableResult
    func setMinimized(_ minimized: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }

    // MARK: Attribute helpers

    private func copy(_ attribute: String) -> Result<CFTypeRef?, ReadError> {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, attribute as CFString, &value) {
        case .success: return .success(value)
        case .cannotComplete: return .failure(.timedOut)
        case .apiDisabled: return .failure(.apiDisabled)
        case .invalidUIElement: return .failure(.gone)
        default: return .success(nil) // unsupported / no value
        }
    }

    private func readPoint(_ attribute: String) -> Result<CGPoint?, ReadError> {
        copy(attribute).map { value in
            guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var p = CGPoint.zero
            return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
        }
    }

    private func readSize(_ attribute: String) -> Result<CGSize?, ReadError> {
        copy(attribute).map { value in
            guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var s = CGSize.zero
            return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
        }
    }

    private func string(_ attribute: String) -> String? {
        guard case .success(let value?) = copy(attribute), CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }

    private func bool(_ attribute: String) -> Bool? {
        guard case .success(let value?) = copy(attribute), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func setPosition(_ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v) == .success
    }

    private func setSize(_ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v) == .success
    }
}
