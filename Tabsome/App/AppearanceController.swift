import AppKit

/// Settings › General › Appearance (PLAN.md §5.13).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` lets AppKit follow macOS, including Auto.
    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

/// Sets `NSApp.appearance` once, so every Tabsome window, panel, and SwiftUI view follows it.
@MainActor
@Observable
final class AppearanceController {
    static let defaultsKey = "appearance"

    var mode: AppearanceMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.defaultsKey)
            apply()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.defaultsKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    func apply(to app: NSApplication? = NSApp) {
        app?.appearance = mode.appearanceName.flatMap(NSAppearance.init(named:))
    }
}
