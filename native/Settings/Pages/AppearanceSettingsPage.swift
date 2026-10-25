import SwiftUI

extension SettingsPane.ID {
    static let appearance = Self("appearance")
}

extension SettingsPane {
    /// Window choices, one current code sample, code font and app icon.
    static let appearance = SettingsPane(
        id: .appearance,
        title: "Appearance",
        systemImage: "paintpalette",
        group: .personal,
        order: 10,
        keywords: [
            "app icon", "dock", "theme", "light", "dark", "dark mode", "light mode", "system", "transparency",
            "translucent", "wool", "paper", "true black", "amoled", "oled", "code theme", "syntax",
        ],
        searchEntries: {
            [
                AppearanceModeSettingsRow.searchEntry, LightToneSettingsRow.searchEntry,
                DarkToneSettingsRow.searchEntry,
                TransparencySettingsRow.searchEntry, PlayfulSpinnersSettingsRow.searchEntry,
                CodeThemeSettingsRow.searchEntry, CodeFontSettingsRow.searchEntry, AccentSettingsRow.searchEntry,
            ]
        },
        content: { AppearanceSettingsContent() }
    )
}
