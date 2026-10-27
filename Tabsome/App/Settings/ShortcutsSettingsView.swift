import KeyboardShortcuts
import SwiftUI

/// Settings › Shortcuts (PLAN.md §7 Phase 6): every tab shortcut, rebindable. Click a field and
/// press the new keys, or clear it to turn that shortcut off. KeyboardShortcuts warns about keys
/// macOS already uses; here, a key another tab shortcut already has is refused.
struct ShortcutsSettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Use keyboard shortcuts", isOn: $model.shortcutsEnabled)
            } footer: {
                Text(model.shortcutsEnabled
                     ? "Shortcuts work only while a tab group is the frontmost window, so the same keys still reach your apps the rest of the time."
                     : "Tabsome doesn’t take any keys. Tabs still work with the mouse and their right-click menus.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Switching tabs") {
                ForEach([HotKeys.Action.next, .previous], id: \.self, content: row)
                // Tab 1–8 in two columns, so the pane fits a small screen without scrolling.
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    ForEach(0..<4, id: \.self) { r in
                        GridRow {
                            ForEach([tabs[r], tabs[r + 4]], id: \.self) { action in
                                Text(action.title)
                                recorder(action).gridColumnAlignment(.trailing)
                            }
                        }
                    }
                }
                row(.last)
            }
            .disabled(!model.shortcutsEnabled)
            Section {
                ForEach([HotKeys.Action.close, .moveToNewWindow, .rename], id: \.self, content: row)
            } header: {
                Text("The active tab")
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore Defaults") { HotKeys.restoreDefaults() }
                }
            }
            .disabled(!model.shortcutsEnabled)
        }
        .formStyle(.grouped)
        .fitsContent()
    }

    private var tabs: [HotKeys.Action] { [.tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8] }

    private func row(_ action: HotKeys.Action) -> some View {
        LabeledContent(action.title) { recorder(action) }
    }

    private func recorder(_ action: HotKeys.Action) -> some View {
        KeyboardShortcuts.Recorder(for: action.name)
            .shortcutValidation { shortcut in
                guard let other = HotKeys.conflict(for: shortcut, excluding: action, current: { $0.name.shortcut }) else { return .allow }
                return .disallow(reason: "This shortcut is already used by “\(other.title)”.")
            }
            .accessibilityLabel(action.title)
    }
}
