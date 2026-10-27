import AppKit
import KeyboardShortcuts
import Testing
@testable import Tabsome

/// Settings › Shortcuts (PLAN.md §7 Phase 6c). Only pure values here: nothing reads or writes
/// the stored shortcuts, so the app's own settings are never touched.
@MainActor
struct ShortcutsTests {
    typealias Action = HotKeys.Action
    let co: NSEvent.ModifierFlags = [.control, .option]

    @Test func defaultsFollowTheBrowserLayoutWithControlOption() {
        #expect(Action.next.initial == .init(.tab, modifiers: co))
        #expect(Action.previous.initial == .init(.tab, modifiers: co.union(.shift)))
        #expect(Action.tab1.initial == .init(.one, modifiers: co))
        #expect(Action.tab8.initial == .init(.eight, modifiers: co))
        #expect(Action.last.initial == .init(.nine, modifiers: co))
        #expect(Action.close.initial == .init(.w, modifiers: co))
        #expect(Action.moveToNewWindow.initial == .init(.n, modifiers: co.union(.shift)))
        #expect(Action.rename.initial == .init(.r, modifiers: co))
    }

    @Test func everyActionHasItsOwnTitle() {
        let titles = Action.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(Action.tab3.title == "Tab 3")
    }

    @Test func aKeyAnotherActionHasIsAConflict() {
        let current: (Action) -> KeyboardShortcuts.Shortcut? = { $0.initial }
        #expect(HotKeys.conflict(for: Action.close.initial, excluding: .rename, current: current) == .close)
        // Recording an action's own key again isn't a conflict.
        #expect(HotKeys.conflict(for: Action.close.initial, excluding: .close, current: current) == nil)
        #expect(HotKeys.conflict(for: .init(.k, modifiers: co), excluding: .close, current: current) == nil)
    }

    @Test func aClearedShortcutConflictsWithNothing() {
        let current: (Action) -> KeyboardShortcuts.Shortcut? = { $0 == .close ? nil : $0.initial }
        #expect(HotKeys.conflict(for: Action.close.initial, excluding: .rename, current: current) == nil)
    }
}
