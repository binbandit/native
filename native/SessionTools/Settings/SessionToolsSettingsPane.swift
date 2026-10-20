import SwiftUI

extension SettingsPane.ID {
    static let sessionTools = Self("sessionTools")
}

extension SettingsPane {
    /// Settings ▸ Session Tools: where each tool on the session screen lives, or that it's off.
    static func sessionTools(_ registry: SessionToolRegistry) -> SettingsPane {
        SettingsPane(
            id: .sessionTools,
            title: "Session Tools",
            systemImage: "rectangle.split.3x1",
            group: .personal,
            order: 14,
            keywords: [
                "changes", "terminal", "run", "workbench", "side panel", "header", "facts", "layout", "toolbar",
            ],
            searchEntries: {
                registry.tools.map {
                    SettingsSearchEntry(id: SessionToolsSettingsPage.row(for: $0.id), title: $0.title)
                }
            },
            content: { SessionToolsSettingsPage(registry: registry) }
        )
    }
}
