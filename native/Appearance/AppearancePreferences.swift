import SwiftUI

/// The user's look-and-feel choices from Settings ▸ Appearance, stored in user defaults.
enum AppearancePreferences {
    /// How see-through the sidebar, overlays and floating controls are (`DSTransparency`).
    static let transparencyKey = "appearance.transparency"
    /// The white light mode is drawn on (`DSLightTone`).
    static let lightToneKey = "appearance.lightTone"
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

    func body(content: Content) -> some View {
        content
            .dsTransparency(transparency)
            .dsLightTone(lightTone)
    }
}
