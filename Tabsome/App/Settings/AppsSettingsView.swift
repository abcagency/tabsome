import SwiftUI
import UniformTypeIdentifiers

/// Settings › Apps (PLAN.md §6.1 S6): apps Tabsome never tabs, with + and − like System
/// Settings' lists. Security windows are never tabbed whether or not they're listed.
struct AppsSettingsView: View {
    let model: AppModel
    @State private var selection: Set<String> = []

    var body: some View {
        Form {
            Section {
                List(model.excludedApps, id: \.self, selection: $selection) { id in
                    ExcludedAppRow(bundleID: id)
                }
                .scrollDisabled(false)
                .frame(height: 176)
                .overlay {
                    if model.excludedApps.isEmpty {
                        Text("No excluded apps").foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 0) {
                    Menu {
                        ForEach(runningCandidates, id: \.bundleIdentifier) { app in
                            Button {
                                add(app.bundleIdentifier)
                            } label: {
                                if let icon = app.icon { Image(nsImage: icon) }
                                Text(app.localizedName ?? app.bundleIdentifier ?? "?")
                            }
                        }
                        if !runningCandidates.isEmpty { Divider() }
                        Button("Choose App…") { chooseApp() }
                    } label: {
                        Image(systemName: "plus").frame(width: 22, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Add App")
                    Divider().frame(height: 14)
                    Button {
                        model.excludedApps.removeAll { selection.contains($0) }
                        selection = []
                    } label: {
                        Image(systemName: "minus").frame(width: 22, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection.isEmpty)
                    .accessibilityLabel("Remove App")
                    Spacer()
                }
            } header: {
                Text("Never tab these apps")
            } footer: {
                Text("Their windows can’t be dragged into groups, and adding an app takes its windows out of groups now. Password managers, Keychain and sign-in prompts, and other security windows are never tabbed, whether or not they’re listed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }

    /// Running apps with windows that aren't excluded already, by name.
    private var runningCandidates: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return !model.excludedApps.contains(id) && !Eligibility.alwaysExcludedBundleIDs.contains(id)
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func add(_ bundleID: String?) {
        guard let bundleID, !model.excludedApps.contains(bundleID) else { return }
        model.excludedApps.append(bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { add(Bundle(url: url)?.bundleIdentifier) }
    }
}

private struct ExcludedAppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
        }
        .padding(.vertical, 1)
    }
}
