import SwiftUI

/// The Settings window skeleton (PLAN.md §7 Phase 1). Tabs, Apps, and Shortcuts arrive with
/// the features they configure.
struct SettingsView: View {
    let model: AppModel
    /// The pane last shown, so Settings reopens where it was left.
    @AppStorage(Self.paneKey) private var pane = "general"
    static let paneKey = "settingsPane"

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: "general") {
                GeneralSettingsView(model: model)
            }
            Tab("Tabs", systemImage: "rectangle.topthird.inset.filled", value: "tabs") {
                TabsSettingsView(model: model)
            }
            Tab("Apps", systemImage: "square.grid.2x2", value: "apps") {
                AppsSettingsView(model: model)
            }
            Tab("About", systemImage: "info.circle", value: "about") {
                AboutSettingsView()
            }
        }
        .frame(width: 520)
    }
}

/// Settings panes never scroll and the window isn't resizable: like the system's own Settings
/// windows, it takes each pane's full height, resizing as you switch tabs. A grouped Form
/// scrolls and would fill whatever height it's given, so it's held to its ideal (content)
/// height instead. No measuring and no state, so layout can't feed back into itself (a
/// measured height crashed the window with a layout loop).
extension View {
    func fitsContent() -> some View {
        scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsView: View {
    let model: AppModel
    @State private var stageManagerOn = StageManager.isOn

    var body: some View {
        @Bindable var appearance = model.appearance
        @Bindable var model = model
        let login = model.launchAtLogin
        Form {
            if stageManagerOn {
                Section {
                    Label("Stage Manager is on", systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    HStack {
                        Text("It moves windows on its own, which conflicts with tabs.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Desktop & Dock…") { StageManager.openSettings() }
                    }
                }
            }
            Section {
                Toggle("Pause Tabsome", isOn: $model.isPaused)
            } footer: {
                Text(model.isPaused
                     ? "Tabsome is paused. Windows can’t be dragged together until you turn this off."
                     : "Pausing undoes every group and leaves all the windows open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
            Section {
                ValueSlider("Pause before tabbing", value: $model.dwellDelay, in: AppModel.dwellDelayRange, step: 0.05,
                            text: { String(format: "%.2f s", $0) })
                ValueSlider("Middle of a window", value: $model.middleZone, in: AppModel.middleZoneRange, step: 0.05,
                            text: { "\(Int(($0 * 100).rounded()))%" })
            } header: {
                Text("Making tabs")
            } footer: {
                Text("Drag a window over the middle of another one and pause to tab them. A smaller middle leaves more of each window’s edges for passing over.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                PermissionRow(title: "Accessibility", granted: model.permissions.accessibility,
                              note: "Needed to move and tab windows.",
                              action: ("Open Privacy & Security…", model.permissions.openAccessibilitySettings))
                PermissionRow(title: "Screen & System Audio Recording", granted: model.permissions.screenRecording,
                              note: "Optional. Previews and animations show app icons without it.",
                              action: ("Allow…", model.permissions.requestScreenRecording))
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .onAppear {
            login.refresh()
            stageManagerOn = StageManager.isOn
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
            stageManagerOn = StageManager.isOn
        }
    }
}

/// A slider row that shows its value on the right.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let text: (Double) -> String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, text: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.text = text
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .labelsHidden()
                    .frame(width: 180)
                Text(text(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One permission's state: a green check when it's allowed, otherwise what it's for and a button.
struct PermissionRow: View {
    let title: String
    let granted: Bool
    let note: String
    let action: (String, () -> Void)

    var body: some View {
        LabeledContent {
            if granted {
                Label {
                    Text("Allowed").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Button(action.0, action: action.1)
            }
        } label: {
            Text(title)
            if !granted { Text(note) }
        }
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

/// Settings › Tabs (PLAN.md §7 Phase 6 has the full list; Tab position comes first so both
/// placements can be used and tested).
struct TabsSettingsView: View {
    let model: AppModel
    @AppStorage(HoverPreview.settingKey) private var showsPreviews = true
    @AppStorage(AppModel.askBeforeClosingAllKey) private var asksBeforeClosingAll = true

    var body: some View {
        @Bindable var model = model
        let position = Binding<TabPlacement>(
            get: { model.tabPlacement.isLeft ? .left : .top },
            set: { model.tabPlacement = $0 == .top ? .top : (UserDefaults.standard.string(forKey: Self.leftStyleKey) == "named" ? .leftNamed : .left) })
        Form {
            Section("Tab position") {
                TabPositionPicker(selection: position)
                    .frame(maxWidth: .infinity)
                if model.tabPlacement.isLeft {
                    Picker("Left tabs", selection: $model.tabPlacement) {
                        Text("Compact (icons only)").tag(TabPlacement.left)
                        Text("With names").tag(TabPlacement.leftNamed)
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: model.tabPlacement) { _, new in
                        if new.isLeft { UserDefaults.standard.set(new == .leftNamed ? "named" : "compact", forKey: Self.leftStyleKey) }
                    }
                }
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Strip size", selection: $model.stripOptions.size) {
                    ForEach(StripSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if !model.tabPlacement.isLeft {
                    ValueSlider("Minimum tab width", value: minTabWidth, in: minTabWidthRange, step: 10,
                                text: { "\(Int($0)) pt" })
                }
                Toggle("Show close buttons on tabs", isOn: $model.stripOptions.showsCloseButtons)
                Toggle("Ask before closing all tabs", isOn: $asksBeforeClosingAll)
            } footer: {
                Text(model.tabPlacement.isLeft
                     ? "Without close buttons, close a tab from its right-click menu. Close All Tabs is in the strip’s right-click menu."
                     : "Narrower tabs show only their icons. Without close buttons, close a tab from its right-click menu. The red button closes all tabs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show app badges on tabs", isOn: $model.stripOptions.showsBadges)
            } footer: {
                Text("When an app shows a badge on its Dock icon, such as Mail’s unread count, its tabs show it too.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show previews when hovering tabs", isOn: $showsPreviews)
            } footer: {
                Text(CGPreflightScreenCaptureAccess()
                     ? "Hover a background tab to see its window."
                     : "Previews show the app’s icon until Tabsome has Screen & System Audio Recording permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}

extension TabsSettingsView {
    /// Remembers which Left style to come back to after switching to Top and back.
    static let leftStyleKey = "leftTabStyle"

    private var minTabWidth: Binding<Double> {
        Binding(get: { Double(model.stripOptions.minTabWidth) }, set: { model.stripOptions.minTabWidth = CGFloat($0) })
    }

    private var minTabWidthRange: ClosedRange<Double> {
        Double(StripOptions.minTabWidthRange.lowerBound)...Double(StripOptions.minTabWidthRange.upperBound)
    }

    var description: String {
        switch model.tabPlacement {
        case .top: "Tabs sit above the window and show each app’s name."
        case .left: "Tabs sit down the window’s left side and show only app icons. Hover a tab for its name."
        case .leftNamed: "Tabs sit down the window’s left side with each tab’s icon and name; long names end in an ellipsis."
        }
    }
}

/// Two small previews: Top shows app names, Left shows icons only.
struct TabPositionPicker: View {
    @Binding var selection: TabPlacement

    var body: some View {
        HStack(spacing: 28) {
            ForEach([TabPlacement.top, .left], id: \.self) { placement in
                Button { selection = placement } label: {
                    VStack(spacing: 6) {
                        preview(placement)
                            .frame(width: 96, height: 62)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selection == placement ? Color.accentColor : Color.secondary.opacity(0.3),
                                                  lineWidth: selection == placement ? 3 : 1)
                            }
                        Text(placement == .top ? "Top" : "Left")
                            .font(.callout)
                            .foregroundStyle(selection == placement ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(placement == .top ? "Tabs on top, with app names" : "Tabs on the left, icons only")
                .accessibilityAddTraits(selection == placement ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func preview(_ placement: TabPlacement) -> some View {
        let window = RoundedRectangle(cornerRadius: 6).fill(.background).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        let chip = { (c: Color) in RoundedRectangle(cornerRadius: 2).fill(c) }
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if placement == .top {
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        ForEach([Color.blue, .orange], id: \.self) { c in
                            HStack(spacing: 2) { chip(c).frame(width: 6, height: 6); Capsule().fill(.secondary).frame(width: 18, height: 3) }
                        }
                        Spacer()
                    }
                    .frame(height: 9)
                    window
                }
                .padding(8)
            } else {
                HStack(spacing: 2) {
                    VStack(spacing: 3) {
                        ForEach([Color.blue, .orange, .green], id: \.self) { c in chip(c).frame(width: 8, height: 8) }
                        Spacer()
                    }
                    .frame(width: 10)
                    window
                }
                .padding(8)
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
