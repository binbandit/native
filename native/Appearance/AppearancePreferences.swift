import CodeThemes
import SwiftUI

/// The user's look-and-feel choices from Settings ▸ Appearance, stored in user defaults.
enum AppearancePreferences {
    /// How see-through the sidebar, overlays and floating controls are (`DSTransparency`).
    static let transparencyKey = "appearance.transparency"
    /// The white light mode is drawn on (`DSLightTone`).
    static let lightToneKey = "appearance.lightTone"
    /// The code themes for light and dark mode (`CodeTheme.ID` raw values).
    static let lightCodeThemeKey = "appearance.codeTheme.light"
    static let darkCodeThemeKey = "appearance.codeTheme.dark"
}

extension View {
    /// Hands the user's appearance choices to the design system for one window. Put it on each
    /// window's root, beside `.dsAccentPalette(themeID:)`.
    func appearancePreferences() -> some View {
        modifier(AppearancePreferencesModifier())
    }
}

private struct AppearancePreferencesModifier: ViewModifier {
    @AppStorage(AppearancePreferences.transparencyKey) private var transparency = DSTransparency.standard
    @AppStorage(AppearancePreferences.lightToneKey) private var lightTone = DSLightTone.paper
    @AppStorage(AppearancePreferences.lightCodeThemeKey) private var lightCodeTheme = CodeTheme.native.id.rawValue
    @AppStorage(AppearancePreferences.darkCodeThemeKey) private var darkCodeTheme = CodeTheme.native.id.rawValue

    func body(content: Content) -> some View {
        content
            .dsTransparency(transparency)
            .dsLightTone(lightTone)
            .dsCodeThemes(DSCodeThemes(light: .init(rawValue: lightCodeTheme), dark: .init(rawValue: darkCodeTheme)))
    }
}
