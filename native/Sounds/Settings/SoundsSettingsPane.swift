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
            keywords: ["chime", "sound", "audio", "notification", "volume"],
            searchEntries: {
                [
                    SettingsSearchEntry(
                        id: SoundsSettingsPage.enabledRow, title: "Play sounds", keywords: ["mute", "silence", "off"]),
                    SettingsSearchEntry(
                        id: SoundsSettingsPage.volumeRow, title: "Volume", keywords: ["loud", "quiet"]),
                    SettingsSearchEntry(
                        id: SoundsSettingsPage.focusRow,
                        title: "Stay quiet during Focus",
                        keywords: ["do not disturb", "dnd", "focus", "quiet"]
                    ),
                    SettingsSearchEntry(
                        id: SoundsSettingsPage.timingRow, title: "When to play", keywords: ["background", "focus"]),
                    SettingsSearchEntry(
                        id: SoundsSettingsPage.folderRow,
                        title: "Sounds folder",
                        keywords: ["folder", "files", "custom", "own sounds", "wav", "mp3", "aiff"]
                    ),
                ]
                    + SoundTrigger.allCases.map {
                        SettingsSearchEntry(
                            id: SoundsSettingsPage.triggerRow($0),
                            title: $0.title,
                            description: $0.detail,
                            keywords: ["chime", "sound", "notification"]
                        )
                    }
            },
            content: { SoundsSettingsPage(sounds: sounds) }
        )
    }
}
