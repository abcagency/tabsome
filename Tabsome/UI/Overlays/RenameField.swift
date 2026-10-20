import AppKit
import SwiftUI

/// Inline tab renaming (PLAN.md §5.10): the whole name starts selected so typing replaces it;
/// Return or clicking elsewhere saves, Esc cancels; at most 60 characters; saving an empty name
/// (or the unchanged default) goes back to the default label.
struct RenameTextField: View {
    let model: TabStripModel
    let tab: TabItem
    let actions: StripActions
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        TextField("Tab name", text: $model.renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .focused($focused)
            .onAppear {
                focused = true
                DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            }
            .onChange(of: model.renameDraft) { _, new in
                if new.count > WindowRegistry.maxNameLength { model.renameDraft = String(new.prefix(WindowRegistry.maxNameLength)) }
            }
            .onSubmit { model.commitRename(refocus: true) }
            .onExitCommand { model.cancelRename() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused, model.renaming == tab.id { model.commitRename(refocus: false) }
            }
            .transition(.opacity)
    }
}

/// Left mode's field, in its own small panel attached to the right of the tab's icon (§5.10).
struct LeftRenameField: View {
    let model: TabStripModel
    let tabID: CGWindowID
    let actions: StripActions

    var body: some View {
        if let tab = model.tabs.first(where: { $0.id == tabID }) {
            RenameTextField(model: model, tab: tab, actions: actions)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: Capsule())
        }
    }
}
