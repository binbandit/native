#if DEBUG
import CodeThemes
import Foundation

struct AppearanceFixturePlugin: NativePlugin {
    let manifest: PluginManifest = {
        let names = ["Dusk", "Moss", "Slate", "Linen"]
        let themes = names.map { name -> ThemeJSON in
            var value: [String: ThemeJSON] = ["id": .string(name.lowercased()), "name": .string(name)]
            let theme: CodeTheme =
                switch name {
                case "Dusk": .rosePine
                case "Moss": .nord
                case "Slate": .github
                default: .rosePine
                }
            if let dark = theme.dark, name != "Linen" { value["dark"] = palette(dark) }
            if let light = theme.light { value["light"] = palette(light) }
            return .object(value)
        }
        return PluginManifest(id: "lantern", name: "Lantern", themes: ThemeContributions(code: themes))
    }()

    private static func palette(_ palette: CodePalette) -> ThemeJSON {
        .object(
            Dictionary(
                uniqueKeysWithValues: CodeTokenRole.allCases.map { role in
                    let color = palette[role]
                    return (
                        role.rawValue,
                        .string(String(format: "#%02X%02X%02X%02X", color.red, color.green, color.blue, color.alpha))
                    )
                }))
    }
}
#endif
