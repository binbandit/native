import AppAppearance
import SwiftUI

extension SettingsPane.ID {
    static let celebrations = Self("celebrations")
}

extension SettingsPane {
    /// Settings ▸ Celebrations: the catalogue all year, each celebration off until chosen.
    static func celebrations(registry: PluginRegistry) -> SettingsPane {
        SettingsPane(
            id: .celebrations,
            title: "Celebrations",
            systemImage: "party.popper",
            group: .extensions,
            order: 30,
            keywords: ["holiday", "festival", "seasonal", "halloween", "app icon", "home", "theme"],
            searchEntries: {
                CelebrationsWiring.catalog(from: registry).celebrations.map { event in
                    SettingsSearchEntry(
                        id: CelebrationsSettingsPage.rowID(event.id), title: event.contribution.title.resolved(),
                        description: event.contribution.summary?.resolved() ?? "",
                        keywords: event.contribution.aliases + event.contribution.tags)
                }
            },
            content: {
                #if DEBUG
                if let name = UserDefaults.standard.string(forKey: "celebrationPreview"),
                    let state = CelebrationPreviewFixtures.State(rawValue: name)
                {
                    CelebrationPreviewGallery(state)
                } else {
                    CelebrationsSettingsPage()
                }
                #else
                CelebrationsSettingsPage()
                #endif
            }
        )
    }
}
