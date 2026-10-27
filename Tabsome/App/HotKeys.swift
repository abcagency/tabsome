import AppKit
import KeyboardShortcuts

/// The browser-layout shortcuts (PLAN.md §5.7), with ⌃⌥ in place of ⌘/⌃ so they never collide
/// with apps' own. KeyboardShortcuts registers them with Carbon's `RegisterEventHotKey`, which
/// needs no Input Monitoring permission, and Tabsome never sees other keystrokes (S5). They're
/// registered only while a group is focused, so the same keys reach other apps the rest of the
/// time. Settings › Shortcuts rebinds them; KeyboardShortcuts keeps the choices in UserDefaults.
@MainActor
final class HotKeys {
    enum Action: UInt32, CaseIterable {
        case next = 1, previous
        case tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8
        case last, close, moveToNewWindow, rename

        var name: KeyboardShortcuts.Name { Self.names[self]! }

        /// What Settings › Shortcuts calls it.
        var title: String {
            switch self {
            case .next: "Next Tab"
            case .previous: "Previous Tab"
            case .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8: "Tab \(rawValue - Self.tab1.rawValue + 1)"
            case .last: "Last Tab"
            case .close: "Close Tab"
            case .moveToNewWindow: "Move Tab to New Window"
            case .rename: "Rename Tab"
            }
        }

        /// The browser layout: ⌃Tab and ⌘1–9 become ⌃⌥Tab and ⌃⌥1–9, and so on.
        var initial: KeyboardShortcuts.Shortcut {
            let co: NSEvent.ModifierFlags = [.control, .option]
            let digits: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight]
            return switch self {
            case .next: .init(.tab, modifiers: co)
            case .previous: .init(.tab, modifiers: co.union(.shift))
            case .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8: .init(digits[Int(rawValue - Self.tab1.rawValue)], modifiers: co)
            case .last: .init(.nine, modifiers: co)
            case .close: .init(.w, modifiers: co)
            case .moveToNewWindow: .init(.n, modifiers: co.union(.shift))
            case .rename: .init(.r, modifiers: co)
            }
        }

        /// Created once: a name stores its initial shortcut the first time it's made.
        private static let names = Dictionary(uniqueKeysWithValues: allCases.map {
            ($0, KeyboardShortcuts.Name("tabsome_\($0)", initial: $0.initial))
        })
    }

    var onAction: ((Action) -> Void)?

    init() {
        // Off until a group is focused (`isEnabled`); handlers alone don't take the keys.
        KeyboardShortcuts.isEnabled = false
        for action in Action.allCases {
            KeyboardShortcuts.onKeyDown(for: action.name) { [weak self] in self?.onAction?(action) }
        }
    }

    /// A group is focused.
    var isEnabled = false {
        didSet { apply() }
    }

    /// Settings › Shortcuts › "Use keyboard shortcuts": off, the keys are never taken, even
    /// while a group is focused.
    var isAllowed = true {
        didSet { apply() }
    }

    private func apply() {
        let on = isEnabled && isAllowed
        if KeyboardShortcuts.isEnabled != on { KeyboardShortcuts.isEnabled = on }
    }

    /// Settings › Shortcuts › Restore Defaults.
    static func restoreDefaults() {
        KeyboardShortcuts.reset(Action.allCases.map(\.name))
    }

    /// The other action already using `shortcut`, if any, so one key never does two things.
    static func conflict(for shortcut: KeyboardShortcuts.Shortcut, excluding action: Action,
                         current: (Action) -> KeyboardShortcuts.Shortcut?) -> Action? {
        Action.allCases.first { $0 != action && current($0) == shortcut }
    }
}
