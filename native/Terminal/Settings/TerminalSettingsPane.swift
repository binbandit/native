import SwiftUI

extension SettingsPane.ID {
    static let terminal = Self("terminal")
}

extension SettingsPane {
    /// Settings › Terminal, for `SettingsView(additionalPanes:)`.
    static func terminal(_ preferences: TerminalPreferences) -> SettingsPane {
        SettingsPane(
            id: .terminal,
            title: "Terminal",
            systemImage: "apple.terminal",
            group: .personal,
            order: 18,
            keywords: ["shell", "console", "ghostty", "pty", "zsh"],
            searchEntries: {
                [
                    SettingsSearchEntry(
                        id: TerminalSettingsPage.fontRow, title: "Font", keywords: ["typeface", "monospace", "family"]),
                    SettingsSearchEntry(id: TerminalSettingsPage.sizeRow, title: "Font size", keywords: ["text size"]),
                    SettingsSearchEntry(
                        id: TerminalSettingsPage.scrollbackRow,
                        title: "Scrollback",
                        description: "How many lines each terminal keeps.",
                        keywords: ["history", "lines", "buffer"]
                    ),
                ]
            },
            content: { TerminalSettingsPage(preferences: preferences) }
        )
    }
}
