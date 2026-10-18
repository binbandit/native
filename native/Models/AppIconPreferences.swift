import AppAppearance
import Foundation
import Observation

/// The app icon: the user's base choice (a built-in theme or a plugin's icon set), in light, dark or
/// the system's appearance, with a celebration on top while one is showing. The base comes back on
/// its own when the celebration ends, and nothing here knows about dates.
@MainActor
@Observable
final class AppIconPreferences {
    /// What the user picked. A plugin set that's switched off or removed shows Original until it's
    /// back, without forgetting the choice.
    private(set) var choice: AppIconOption.ID {
        didSet {
            defaults.set(choice.rawValue, forKey: Self.themeKey)
            apply()
        }
    }

    var appearance: AppIconAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
            apply()
        }
    }

    /// Plain icon sets from enabled plugins, offered beside the built-in themes.
    var iconSets: [IconSet] = [] {
        didSet { apply() }
    }

    /// Plugin names by id, to credit an icon set in the picker.
    var pluginNames: [String: String] = [:]

    /// The celebration on the icon, set by `CelebrationCenter`; it covers the base until it ends.
    var celebration: AppIconCelebration? {
        didSet {
            guard celebration != oldValue else { return }
            apply()
        }
    }

    /// Whether Native's appearance is dark: the system's, unless Settings ▸ Appearance sets one.
    private(set) var appearanceIsDark = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let variant: AppIconVariant
    @ObservationIgnored private let platform = PlatformAppIcon()
    @ObservationIgnored private var hasStarted = false

    private static let themeKey = "appIconTheme"
    private static let appearanceKey = "appIconAppearance"

    init(defaults: UserDefaults = .standard, variant: AppIconVariant = .current) {
        self.defaults = defaults
        self.variant = variant
        if defaults.string(forKey: Self.themeKey) == "glass" {
            defaults.set(AppIconTheme.original.rawValue, forKey: Self.themeKey)
        }
        choice = defaults.string(forKey: Self.themeKey).map(AppIconOption.ID.init(rawValue:)) ?? .theme(.original)
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(AppIconAppearance.init(rawValue:)) ?? .system
    }

    // MARK: - The base icon

    var options: [AppIconOption] {
        AppIconOption.all(iconSets: iconSets, pluginNames: pluginNames, variant: variant)
    }

    /// The chosen plugin icon set, while an enabled plugin provides it.
    var baseIconSet: IconSet? {
        choice.iconSet.flatMap { id in iconSets.first { $0.id == id } }
    }

    /// The built-in theme in effect: the chosen one, or Original under a plugin set or a missing one.
    /// The accent palette follows it.
    var theme: AppIconTheme {
        choice.theme ?? .original
    }

    /// The choice the picker marks: Original while a chosen plugin set is unavailable.
    var effectiveChoice: AppIconOption.ID {
        choice.theme != nil || baseIconSet != nil ? choice : .theme(.original)
    }

    func select(_ id: AppIconOption.ID) {
        choice = id
    }

    /// The base icon's images for this build, or nil for the compiled icon.
    private var baseImages: AppIconImagePair? {
        if let baseIconSet { return baseIconSet.icons[variant] }
        return theme == .original ? nil : theme.images
    }

    /// How Home dresses up for the base icon: a plugin set's mark or palette.
    var baseHomeLook: HomeLook? {
        baseIconSet?.home
    }

    // MARK: - What's showing

    var isCelebrating: Bool { celebration != nil }

    /// Whether the compiled icon shows, with every system appearance (Default, Dark, Clear, Tinted).
    var usesSystemIcon: Bool { currentImages == nil }

    var displayName: String {
        if let celebration { return "\(celebration.title) · \(variant.displayName)" }
        if let baseIconSet { return baseIconSet.name.resolved() }
        return theme == .original ? variant.displayName : theme.title
    }

    var isDark: Bool {
        if usesSystemIcon { return appearanceIsDark }
        return switch appearance {
        case .system: appearanceIsDark
        case .light: false
        case .dark: true
        }
    }

    /// The image the Dock shows, or nil for the compiled icon.
    var currentImage: AppIconImage? {
        currentImages?.image(isDark: isDark)
    }

    private var currentImages: AppIconImagePair? {
        celebration?.icons ?? baseImages
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        platform.onAppearanceChange = { [weak self] isDark in
            self?.appearanceIsDark = isDark
            self?.apply()
        }
        platform.start()
    }

    private func apply() {
        guard hasStarted else { return }
        platform.apply(currentImage.flatMap { PlatformAppIcon.canApply($0) ? $0 : nil })
    }
}

/// A celebration's icon for this build's channel, as `CelebrationCenter` hands it over.
struct AppIconCelebration: Equatable {
    let title: String
    let icons: AppIconImagePair
}
