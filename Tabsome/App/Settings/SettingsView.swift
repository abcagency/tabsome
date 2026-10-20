import SwiftUI

/// The Settings window skeleton (PLAN.md §7 Phase 1). Tabs, Apps, and Shortcuts arrive with
/// the features they configure.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(model: model)
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .frame(width: 520)
    }
}

struct GeneralSettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var appearance = model.appearance
        let login = model.launchAtLogin
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { login.isEnabled || login.needsApproval }, set: { login.set($0) }))
                if login.needsApproval {
                    HStack {
                        Text("macOS needs your approval in Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { login.openLoginItems() }
                    }
                }
                if let error = login.lastError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }
            Section("Appearance") {
                AppearancePicker(selection: $appearance.mode)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }
}

/// Three thumbnails like System Settings › Appearance (PLAN.md §5.13).
struct AppearancePicker: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: 24) {
            ForEach(AppearanceMode.allCases) { mode in
                Button { selection = mode } label: {
                    VStack(spacing: 6) {
                        AppearanceThumbnail(mode: mode)
                            .frame(width: 76, height: 50)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selection == mode ? Color.accentColor : Color.secondary.opacity(0.3),
                                                  lineWidth: selection == mode ? 3 : 1)
                            }
                        Text(mode.title)
                            .font(.callout)
                            .foregroundStyle(selection == mode ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// A tiny desktop with a window, drawn in the scheme it stands for (System shows both).
struct AppearanceThumbnail: View {
    let mode: AppearanceMode

    var body: some View {
        switch mode {
        case .light: scene(dark: false)
        case .dark: scene(dark: true)
        case .system:
            ZStack {
                scene(dark: false)
                scene(dark: true).mask(Diagonal())
            }
        }
    }

    private func scene(dark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: dark ? [Color(white: 0.25), Color(white: 0.1)] : [Color(red: 0.62, green: 0.78, blue: 0.98), Color(red: 0.42, green: 0.62, blue: 0.95)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                VStack(spacing: 0) {
                    Rectangle().fill(dark ? Color(white: 0.24) : Color(white: 0.92)).frame(height: 8)
                        .overlay(alignment: .leading) {
                            HStack(spacing: 2) {
                                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 3, height: 3) }
                            }
                            .padding(.leading, 3)
                        }
                    Rectangle().fill(dark ? Color(white: 0.16) : .white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private struct Diagonal: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                p.closeSubpath()
            }
        }
    }
}

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(Brand.name).font(.title2.bold())
            Text(version).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}
