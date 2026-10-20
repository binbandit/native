import SwiftUI

/// Settings ▸ Appearance ▸ Accent: follow the app icon's theme (the default) or use an accent palette
/// a plugin provides. Only shown once a plugin offers one, or while one is chosen.
struct AccentSettingsRow: View {
    static let rowID = SettingsRowID("appearance.accent")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID, title: "Accent", description: "Follow the app icon's colors, or use a plugin's accent.",
            keywords: ["accent", "color", "tint", "plugin"])
    }

    @AppStorage(AppearancePreferences.accentKey) private var selection = ""
    @Environment(PluginRegistry.self) private var plugins

    var body: some View {
        let accents = PluginThemeCatalog(plugins).accents
        if !accents.isEmpty || !selection.isEmpty {
            row(accents)
        }
    }

    private func row(_ accents: [DSAccentPalette]) -> some View {
        SettingsRow(
            id: Self.rowID,
            "Accent",
            description: Text("The color of your own actions: send, update and primary buttons."),
            detail: selection.isEmpty || accents.contains(where: { $0.id == selection })
                ? nil : Text("The plugin that provided your accent is off, so Native follows the app icon.")
        ) {
            SettingsSelect(
                label: "Accent",
                selection: $selection,
                options: [.init(value: "", title: "Match app icon")]
                    + accents.map { .init(value: $0.id, title: $0.name) },
                width: SettingsMetrics.selectWidth * 1.6
            )
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Accent row") {
    DSPreviewPair {
        SettingsRowGroup {
            AccentSettingsRow()
        }
        .settingsPreviewPage()
    }
    .environment(SettingsPreviewFixtures.registry())
}
#endif
