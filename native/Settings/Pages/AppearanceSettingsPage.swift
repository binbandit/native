import SwiftUI

extension SettingsPane.ID {
    static let appearance = Self("appearance")
}

extension SettingsPane {
    /// Hosts the app icon picker, which another contributor owns, as it is.
    static let appearance = SettingsPane(
        id: .appearance,
        title: "Appearance",
        systemImage: "paintpalette",
        group: .personal,
        order: 10,
        keywords: ["app icon", "dock", "theme", "light", "dark"],
        content: {
            SettingsPage {
                SettingsHeader("Appearance")
                AppearanceSettingsView()
            }
        }
    )
}
