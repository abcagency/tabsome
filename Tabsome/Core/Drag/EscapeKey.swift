import Carbon
import Foundation

/// Esc cancels a drag, like Chrome's tab drags (PLAN.md §7 Phase 6f). A Carbon hot key, so
/// there's no Input Monitoring permission and Tabsome never sees other keystrokes (S5). It's
/// registered only while one of Tabsome's drags is underway, so Esc reaches apps otherwise.
@MainActor
final class EscapeKey {
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x5462_4573 // 'TbEs'

    var isArmed = false {
        didSet {
            guard isArmed != oldValue else { return }
            isArmed ? register() : unregister()
        }
    }

    private func register() {
        installHandlerOnce()
        var hotKey: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        if RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &hotKey) == noErr { ref = hotKey }
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerOnce() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon -> OSStatus in
            guard let event, let refcon else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == EscapeKey.signature else { return OSStatus(eventNotHandledErr) }
            let key = Unmanaged<EscapeKey>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { key.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
