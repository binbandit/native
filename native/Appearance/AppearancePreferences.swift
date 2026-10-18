import CodeThemes
import SwiftUI

/// The user's look-and-feel choices from Settings ▸ Appearance, stored in user defaults.
///
/// Keys have no dots: `@AppStorage` learns of a change through key-value observing, which reads a
/// dot as a key path, so a dotted key never reported one and other views showing the setting went
/// stale. `migrateDottedKeys()` moves choices saved under the old dotted keys.
enum AppearancePreferences {
    /// Light, dark or the system's (`AppearanceMode`), applied by `AppearanceModeController`.
    static let modeKey = "appearanceMode"
    /// How see-through the sidebar, overlays and floating controls are (`DSTransparency`).
    static let transparencyKey = "appearanceTransparency"
    /// The white light mode is drawn on (`DSLightTone`).
    static let lightToneKey = "appearanceLightTone"
    /// The code themes for light and dark mode (`CodeTheme.ID` raw values).
    static let lightCodeThemeKey = "appearanceCodeThemeLight"
    static let darkCodeThemeKey = "appearanceCodeThemeDark"
    /// A plugin accent palette's id, or empty to follow the app icon's theme.
    static let accentKey = "appearanceAccent"
    /// The code font (`DSCodeFont`): an installed monospaced family (empty for Geist Mono), its size,
    /// line height and ligatures.
    static let codeFontFamilyKey = "appearanceCodeFontFamily"
    static let codeFontSizeKey = "appearanceCodeFontSize"
    static let codeLineHeightKey = "appearanceCodeLineHeight"
    static let codeLigaturesKey = "appearanceCodeLigatures"
    /// The terminal uses the code font and size too (`TerminalSettings.fontFamily`, `fontSize`).
    static let terminalUsesCodeFontKey = "appearanceCodeFontTerminal"

    /// Moves choices saved under the old dotted keys to the current ones, once. Run it before any
    /// view reads them.
    static func migrateDottedKeys(in defaults: UserDefaults = .standard) {
        let renamed = [
            "appearance.transparency": transparencyKey,
            "appearance.lightTone": lightToneKey,
            "appearance.codeTheme.light": lightCodeThemeKey,
            "appearance.codeTheme.dark": darkCodeThemeKey,
            "appearance.accent": accentKey,
            "appearance.codeFont.family": codeFontFamilyKey,
            "appearance.codeFont.size": codeFontSizeKey,
            "appearance.codeFont.lineHeight": codeLineHeightKey,
            "appearance.codeFont.ligatures": codeLigaturesKey,
            "appearance.codeFont.terminal": terminalUsesCodeFontKey,
        ]
        for (old, new) in renamed {
            guard let value = defaults.object(forKey: old) else { continue }
            if defaults.object(forKey: new) == nil {
                defaults.set(value, forKey: new)
            }
            defaults.removeObject(forKey: old)
        }
    }
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
