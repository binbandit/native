import Foundation
import Observation
import SwiftUI

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

    /// Light or dark as the app shows now: the chosen mode, or the system's under Auto.
    var effectiveScheme: ColorScheme { mode.colorScheme ?? platform.current }

    /// Shows the app in `scheme` for a moment without choosing it (Try On's other mode); nil shows
    /// the chosen mode again.
    func preview(_ scheme: ColorScheme?) {
        platform.apply(scheme ?? mode.colorScheme)
    }

    /// Applies the saved choice at once, so the first window opens in it.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: AppearancePreferences.modeKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        platform.apply(mode.colorScheme)
    }
}
