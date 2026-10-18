import SwiftUI

extension SettingsPane.ID {
    static let appearance = Self("appearance")
}

extension SettingsPane {
    /// The look of the app: the app icon (Mac-only, since the icon is the Dock's), the white light mode
    /// is drawn on, and how see-through the translucent layers are.
    static let appearance = SettingsPane(
        id: .appearance,
        title: "Appearance",
        systemImage: "paintpalette",
        group: .personal,
        order: 10,
        keywords: ["app icon", "dock", "theme", "light", "dark", "transparency", "translucent", "wool", "paper"],
        searchEntries: { [LightToneSettingsRow.searchEntry, TransparencySettingsRow.searchEntry] },
        content: {
            SettingsPage {
                SettingsHeader("Appearance")
                #if os(macOS)
                AppearanceSettingsView()
                SeparatorLine()
                #endif
                SettingsRowGroup {
                    LightToneSettingsRow()
                    TransparencySettingsRow()
                }
            }
        }
    )
}
