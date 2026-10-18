import CodeThemes
import SwiftUI

/// The user's look-and-feel choices from Settings ▸ Appearance, stored in user defaults.
enum AppearancePreferences {
    /// Light, dark or the system's (`AppearanceMode`), applied by `AppearanceModeController`.
    static let modeKey = "appearance.mode"
    /// How see-through the sidebar, overlays and floating controls are (`DSTransparency`).
    static let transparencyKey = "appearance.transparency"
    /// The white light mode is drawn on (`DSLightTone`).
    static let lightToneKey = "appearance.lightTone"
    /// The black dark mode is drawn on (`DSDarkTone`).
    static let darkToneKey = "appearance.darkTone"
    /// The code themes for light and dark mode (`CodeTheme.ID` raw values).
    static let lightCodeThemeKey = "appearance.codeTheme.light"
    static let darkCodeThemeKey = "appearance.codeTheme.dark"
    /// A plugin accent palette's id, or empty to follow the app icon's theme.
    static let accentKey = "appearance.accent"
    /// The code font (`DSCodeFont`): an installed monospaced family (empty for Geist Mono), its size,
    /// line height and ligatures.
    static let codeFontFamilyKey = "appearance.codeFont.family"
    static let codeFontSizeKey = "appearance.codeFont.size"
    static let codeLineHeightKey = "appearance.codeFont.lineHeight"
    static let codeLigaturesKey = "appearance.codeFont.ligatures"
    /// The terminal uses the code font and size too (`TerminalSettings.fontFamily`, `fontSize`).
    static let terminalUsesCodeFontKey = "appearance.codeFont.terminal"
}

extension View {
    /// Hands the user's appearance choices to the design system for one window. Put it on each
    /// window's root, just inside `.dsAccentPalette(themeID:)`, so a plugin accent the user picked
    /// overrides the icon theme's. `plugins` supplies plugin themes.
    func appearancePreferences(plugins: PluginRegistry) -> some View {
        modifier(AppearancePreferencesModifier(plugins: plugins))
    }
}

private struct AppearancePreferencesModifier: ViewModifier {
    let plugins: PluginRegistry

    @AppStorage(AppearancePreferences.transparencyKey) private var transparency = DSTransparency.standard
    @AppStorage(AppearancePreferences.lightToneKey) private var lightTone = DSLightTone.paper
    @AppStorage(AppearancePreferences.darkToneKey) private var darkTone = DSDarkTone.standard
    @AppStorage(AppearancePreferences.lightCodeThemeKey) private var lightCodeTheme = CodeTheme.native.id.rawValue
    @AppStorage(AppearancePreferences.darkCodeThemeKey) private var darkCodeTheme = CodeTheme.native.id.rawValue
    @AppStorage(AppearancePreferences.accentKey) private var accent = ""
    @AppStorage(AppearancePreferences.codeFontFamilyKey) private var codeFamily = DSCodeFont.standard.family
    @AppStorage(AppearancePreferences.codeFontSizeKey) private var codeSize = DSCodeFont.standard.size
    @AppStorage(AppearancePreferences.codeLineHeightKey) private var codeLineHeight = DSCodeFont.standard.lineHeight
    @AppStorage(AppearancePreferences.codeLigaturesKey) private var codeLigatures = DSCodeFont.standard.ligatures

    func body(content: Content) -> some View {
        // A theme or accent whose plugin is off (or gone) falls back to the default at once.
        let catalog = PluginThemeCatalog(plugins)
        content
            .dsTransparency(transparency)
            .dsLightTone(lightTone)
            .dsDarkTone(darkTone)
            .dsCodeThemes(
                DSCodeThemes(
                    light: catalog.codeTheme(id: lightCodeTheme) ?? .native,
                    dark: catalog.codeTheme(id: darkCodeTheme) ?? .native)
            )
            .dsCodeFont(
                DSCodeFont(family: codeFamily, size: codeSize, lineHeight: codeLineHeight, ligatures: codeLigatures)
            )
            .modifier(PluginAccent(palette: catalog.accent(id: accent)))
    }
}

/// A plugin accent the user picked, over the icon theme's; the icon theme's when they follow it.
/// One branch either way, so switching accents keeps every view's state.
private struct PluginAccent: ViewModifier {
    let palette: DSAccentPalette?

    @Environment(\.dsAccentPalette) private var iconPalette

    func body(content: Content) -> some View {
        content.dsAccentPalette(palette ?? iconPalette)
    }
}
