import SwiftUI

extension SettingsPane.ID {
    static let sounds = Self("sounds")
}

extension SettingsPane {
    /// Settings › Sounds, for `SettingsView(additionalPanes:)`.
    static func sounds(_ sounds: NotificationSounds = .shared) -> SettingsPane {
        SettingsPane(
            id: .sounds,
            title: "Sounds",
            systemImage: "speaker.wave.2",
            group: .personal,
            order: 15,
            keywords: ["chime", "sound", "audio", "notification", "volume", "conductor"],
            searchEntries: {
                [
                    SettingsSearchEntry(id: SoundsSettingsPage.enabledRow, title: "Play sounds", keywords: ["mute", "silence", "off"]),
                    SettingsSearchEntry(
                        id: SoundsSettingsPage.focusRow,
                        title: "Stay quiet during Focus",
                        keywords: ["do not disturb", "dnd", "focus", "quiet"]
                    ),
                    SettingsSearchEntry(
                        id: SoundsSettingsPage.soundRow,
                        title: "Notification sound",
                        description: "Choose what plays when a task finishes or needs you.",
                        keywords: ["chime", "bell", "completion"]
                    ),
                    SettingsSearchEntry(id: SoundsSettingsPage.volumeRow, title: "Volume", keywords: ["loud", "quiet"]),
                    SettingsSearchEntry(id: SoundsSettingsPage.timingRow, title: "When to play", keywords: ["background", "focus"]),
                ] + SoundTrigger.allCases.map {
                    SettingsSearchEntry(id: SoundsSettingsPage.triggerRow($0), title: $0.title, description: $0.detail)
                }
            },
            content: { SoundsSettingsPage(sounds: sounds) }
        )
    }
}
