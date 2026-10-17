import AppKit
import Observation

enum AppIconTheme: String, CaseIterable, Identifiable {
    case original, cobalt, fern, ember, prism, arcade, nightly

    var id: Self { self }

    var title: String { rawValue.capitalized }

    func imageName(isDark: Bool) -> String {
        "AppIcon-\(rawValue)-\(isDark ? "dark" : "light")"
    }
}

enum AppIconAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

@MainActor
@Observable
final class AppIconPreferences {
    var theme: AppIconTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.themeKey)
            apply()
        }
    }

    var appearance: AppIconAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
            apply()
        }
    }

    private(set) var systemIsDark = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    private static let themeKey = "appIconTheme"
    private static let appearanceKey = "appIconAppearance"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Self.themeKey).flatMap(AppIconTheme.init(rawValue:)) ?? .original
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(AppIconAppearance.init(rawValue:)) ?? .system
        if defaults.string(forKey: Self.themeKey) == "glass" {
            defaults.set(AppIconTheme.original.rawValue, forKey: Self.themeKey)
        }
    }

    var isDark: Bool {
        if theme == .original { return systemIsDark }
        return switch appearance {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }

    var imageName: String { theme.imageName(isDark: isDark) }

    func start() {
        guard appearanceObservation == nil else { return }
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateSystemAppearance()
            }
        }
        updateSystemAppearance()
    }

    private func updateSystemAppearance() {
        systemIsDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        apply()
    }

    private func apply() {
        if theme == .original {
            // Keep the native icon stack so macOS controls Default, Dark, Clear and Tinted appearances.
            NSApplication.shared.applicationIconImage = nil
        } else {
            NSApplication.shared.applicationIconImage = NSImage(named: imageName)
        }
    }
}
