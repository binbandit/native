import Foundation
import Observation

/// Native's light or dark appearance, for the whole app and live. It's set on the app itself
/// (`PlatformAppearance`) rather than on SwiftUI views, so everything follows: every window, sheet,
/// popover and menu, AppKit views like the sidebar's material and text views, and what reads the
/// color scheme from them (the light tone, code themes, Home's artwork, the terminal, the icon's
/// Automatic appearance).
@MainActor
@Observable
final class AppearanceModeController {
    var mode: AppearanceMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: AppearancePreferences.modeKey)
            platform.apply(mode.colorScheme)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let platform = PlatformAppearance()

    /// Applies the saved choice at once, so the first window opens in it.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: AppearancePreferences.modeKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        platform.apply(mode.colorScheme)
    }
}
