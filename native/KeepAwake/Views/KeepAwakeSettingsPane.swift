import SwiftUI

extension SettingsPane.ID {
    static let keepAwake = Self("keepAwake")
}

extension SettingsPane {
    /// Settings › Keep Awake, for `SettingsView(additionalPanes:)`.
    static func keepAwake(_ controller: KeepAwakeController) -> SettingsPane {
        SettingsPane(
            id: .keepAwake,
            title: "Keep Awake",
            systemImage: "cup.and.saucer",
            group: .personal,
            order: 16,
            keywords: ["caffeinate", "sleep", "awake", "power", "battery", "display", "lid"],
            searchEntries: {
                [
                    SettingsSearchEntry(
                        id: KeepAwakeSettingsPage.modeRow,
                        title: "Keep Mac awake",
                        description: "Prevents idle sleep while agents work, or always.",
                        keywords: ["caffeinate", "sleep", "agents"]
                    ),
                    SettingsSearchEntry(id: KeepAwakeSettingsPage.timerRow, title: "Stay awake for a while", keywords: ["timer", "hours"]),
                    SettingsSearchEntry(id: KeepAwakeSettingsPage.displayRow, title: "Keep display on", keywords: ["screen", "dim"]),
                    SettingsSearchEntry(id: KeepAwakeSettingsPage.batteryRow, title: "On battery", keywords: ["power", "plugged in"]),
                ]
            },
            content: { KeepAwakeSettingsPage(controller: controller) }
        )
    }
}
