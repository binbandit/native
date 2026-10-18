import AppAppearance
import Foundation
import Observation

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

    var halloweenEnabled: Bool {
        didSet {
            defaults.set(halloweenEnabled, forKey: Self.halloweenKey)
            apply()
        }
    }

    private(set) var systemIsDark = false
    private(set) var isHalloweenAvailable: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let variant: AppIconVariant
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private let platform = PlatformAppIcon()
    @ObservationIgnored private var seasonalTimer: Timer?
    @ObservationIgnored private var hasStarted = false

    private static let themeKey = "appIconTheme"
    private static let appearanceKey = "appIconAppearance"
    private static let halloweenKey = "appIconHalloweenEnabled"

    init(
        defaults: UserDefaults = .standard,
        variant: AppIconVariant = .current,
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.defaults = defaults
        self.variant = variant
        self.now = now
        self.timeZone = timeZone
        theme = defaults.string(forKey: Self.themeKey).flatMap(AppIconTheme.init(rawValue:)) ?? .original
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(AppIconAppearance.init(rawValue:)) ?? .system
        halloweenEnabled = defaults.bool(forKey: Self.halloweenKey)
        isHalloweenAvailable = SeasonalAppIcons.halloweenIsAvailable(on: now(), timeZone: timeZone())
        if defaults.string(forKey: Self.themeKey) == "glass" {
            defaults.set(AppIconTheme.original.rawValue, forKey: Self.themeKey)
        }
    }

    var isHalloweenActive: Bool { halloweenEnabled && isHalloweenAvailable }
    var usesSystemIcon: Bool { theme == .original && !isHalloweenActive }
    var displayName: String {
        if isHalloweenActive { return "Halloween · \(variant.displayName)" }
        return theme == .original ? variant.displayName : theme.title
    }

    var isDark: Bool {
        if usesSystemIcon { return systemIsDark }
        return switch appearance {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }

    var imageName: String {
        if isHalloweenActive { return halloweenImageName }
        return theme == .original ? variant.imageName(isDark: isDark) : theme.imageName(isDark: isDark)
    }

    var halloweenImageName: String {
        variant.halloweenImageName(isDark: isDark)
    }

    func selectTheme(_ theme: AppIconTheme) {
        self.theme = theme
        halloweenEnabled = false
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        platform.onEnvironmentChange = { [weak self] isDark in
            self?.systemIsDark = isDark
            self?.refreshSeason()
        }
        platform.start()
    }

    /// Re-evaluated on activation, wake, clock/time-zone changes and the seasonal boundary itself.
    func refreshSeason() {
        let date = now()
        let zone = timeZone()
        isHalloweenAvailable = SeasonalAppIcons.halloweenIsAvailable(on: date, timeZone: zone)
        seasonalTimer?.invalidate()
        if let boundary = SeasonalAppIcons.nextHalloweenBoundary(after: date, timeZone: zone) {
            seasonalTimer = Timer.scheduledTimer(
                withTimeInterval: max(1, boundary.timeIntervalSince(date)), repeats: false
            ) {
                [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshSeason() }
            }
        }
        apply()
    }

    private func apply() {
        platform.apply(imageNamed: usesSystemIcon ? nil : imageName)
    }

    isolated deinit { seasonalTimer?.invalidate() }
}
