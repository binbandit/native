import CodeThemes
import SwiftUI

/// The themes enabled plugins declare (`plugin.json` `themes`), checked and labelled with their
/// plugin's name, beside the built-in ones. A theme that fails its checks is left out and reported
/// on the plugin's row in Settings ▸ Extensions; a disabled plugin's themes simply aren't here, so
/// a choice of one falls back to the default.
struct PluginThemeCatalog {
    struct Entry: Identifiable {
        let theme: CodeTheme
        let pluginName: String?
        var id: CodeTheme.ID { theme.id }
    }

    var entries: [Entry] { allCodeThemes.map { Entry(theme: $0, pluginName: pluginNames[$0.id]) } }

    private(set) var codeThemes: [CodeTheme] = []
    private(set) var pluginNames: [CodeTheme.ID: String] = [:]
    private(set) var accents: [DSAccentPalette] = []

    init(_ registry: PluginRegistry) {
        for plugin in registry.enabledPlugins {
            let checked = Self.check(plugin.manifest)
            codeThemes += checked.codeThemes
            for theme in checked.codeThemes { pluginNames[theme.id] = plugin.manifest.name }
            accents += checked.accents
        }
    }

    /// Built-in code themes, then plugins'.
    var allCodeThemes: [CodeTheme] { CodeTheme.all + codeThemes }

    func codeTheme(id: String) -> CodeTheme? {
        allCodeThemes.first { $0.id.rawValue == id }
    }

    func accent(id: String) -> DSAccentPalette? {
        accents.first { $0.id == id }
    }

    /// One plugin's themes, checked: the usable ones with their original names, and why the others aren't.
    static func check(
        _ manifest: PluginManifest
    ) -> (codeThemes: [CodeTheme], accents: [DSAccentPalette], problems: [ThemeProblem]) {
        var codeThemes: [CodeTheme] = []
        var accents: [DSAccentPalette] = []
        var problems: [ThemeProblem] = []
        for result in manifest.themes.codeThemes(namespace: manifest.id) {
            switch result {
            case .success(let theme): codeThemes.append(theme)
            case .failure(let error): problems.append(error.problem)
            }
        }
        let backgrounds = AccentBackgrounds.current
        for result in manifest.themes.accents(
            namespace: manifest.id, lightBackgrounds: backgrounds.light, darkBackgrounds: backgrounds.dark)
        {
            switch result {
            case .success(let accent): accents.append(DSAccentPalette(accent, plugin: manifest.name))
            case .failure(let error): problems.append(error.problem)
            }
        }
        return (codeThemes, accents, problems)
    }
}

/// The backgrounds accent text must read on: light and dark mode's in every tone, taken from the
/// design system so the check follows the tokens.
private enum AccentBackgrounds {
    @MainActor static let current: (light: [CodeColor], dark: [CodeColor]) = {
        func background(_ scheme: ColorScheme, _ light: DSLightTone, _ dark: DSDarkTone) -> CodeColor {
            CodeColor(
                Color.dsBackground.resolve(
                    in: .code(colorScheme: scheme, lightTone: light, darkTone: dark, themes: .native)))
        }
        return (
            DSLightTone.allCases.map { background(.light, $0, .standard) },
            DSDarkTone.allCases.map { background(.dark, .paper, $0) }
        )
    }()
}

extension DSAccentPalette {
    /// A plugin's accent, named with its plugin.
    fileprivate init(_ accent: AccentContribution, plugin: String) {
        func swatch(_ swatch: AccentContribution.Swatch) -> Swatch {
            func hex(_ color: CodeColor) -> UInt32 {
                UInt32(color.red) << 16 | UInt32(color.green) << 8 | UInt32(color.blue)
            }
            return Swatch(
                accent: hex(swatch.accent), hover: hex(swatch.hover), pressed: hex(swatch.pressed),
                text: hex(swatch.text), onAccent: hex(swatch.onAccent), subtle: hex(swatch.subtle))
        }
        self.init(
            id: accent.id, name: "\(accent.name) (\(plugin))", light: swatch(accent.light), dark: swatch(accent.dark))
    }
}
