import SwiftUI

extension SettingsPane.ID {
    static let appearance = Self("appearance")
}

extension SettingsPane {
    /// The look of the app: the app icon (another contributor's view, hosted as it is, and Mac-only
    /// since the icon is the Dock's) and the transparency of the translucent layers.
    static let appearance = SettingsPane(
        id: .appearance,
        title: "Appearance",
        systemImage: "paintpalette",
        group: .personal,
        order: 10,
        keywords: ["app icon", "dock", "theme", "light", "dark", "transparency", "translucent"],
        searchEntries: { [TransparencySettingsRow.searchEntry] },
        content: {
            SettingsPage {
                SettingsHeader("Appearance")
                #if os(macOS)
                AppearanceSettingsView()
                SeparatorLine()
                #endif
                TransparencySettingsRow()
            }
        }
    )
}
