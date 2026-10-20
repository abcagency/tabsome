import Carbon
import Foundation

/// The browser-layout shortcuts (PLAN.md §5.7), with ⌃⌥ in place of ⌘/⌃ so they never collide
/// with apps' own. `RegisterEventHotKey` needs no Input Monitoring permission, and Tabsome never
/// sees other keystrokes (S5). They're registered only while a group is focused, so the same
/// keys reach other apps the rest of the time. Settings › Shortcuts makes them rebindable (Phase 6).
@MainActor
final class HotKeys {
    enum Action: UInt32, CaseIterable {
        case next = 1, previous
        case tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8
        case last, close, moveToNewWindow, rename
    }

    var onAction: ((Action) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x5462_736D // 'Tbsm'

    /// Key code and Carbon modifiers for each action.
    static let bindings: [(Action, Int, Int)] = {
        let co = controlKey | optionKey
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8]
        let tabs: [Action] = [.tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8]
        return [(.next, kVK_Tab, co), (.previous, kVK_Tab, co | shiftKey)]
            + zip(tabs, digits).map { ($0, $1, co) }
            + [(.last, kVK_ANSI_9, co), (.close, kVK_ANSI_W, co), (.moveToNewWindow, kVK_ANSI_N, co | shiftKey), (.rename, kVK_ANSI_R, co)]
    }()

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? register() : unregister()
        }
    }

    private func register() {
        installHandlerOnce()
        for (action, key, modifiers) in Self.bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            if RegisterEventHotKey(UInt32(key), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    private func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func installHandlerOnce() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon -> OSStatus in
            guard let event, let refcon else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotKeys.signature, let action = HotKeys.Action(rawValue: id.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { hotKeys.onAction?(action) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
