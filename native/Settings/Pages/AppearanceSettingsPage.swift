import SwiftUI

extension SettingsPane.ID {
    static let appearance = Self("appearance")
}

extension SettingsPane {
    /// The look of the app: light, dark or the system's first, then the white light mode and the
    /// black dark mode are drawn on, the app icon (Mac-only, since the icon is the Dock's), how
    /// see-through the translucent layers are, the accent, and the code font and theme.
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
        content: {
            SettingsPage {
                SettingsHeader("Appearance")
                SettingsRowGroup {
                    AppearanceModeSettingsRow()
                    LightToneSettingsRow()
                    DarkToneSettingsRow()
                    PlayfulSpinnersSettingsRow()
                }
                SeparatorLine()
                #if os(macOS)
                AppearanceSettingsView()
                SeparatorLine()
                #endif
                SettingsRowGroup {
                    TransparencySettingsRow()
                    AccentSettingsRow()
                    CodeFontSettingsRow()
                    CodeThemeSettingsRow()
                }
            }
        }
    )
}
