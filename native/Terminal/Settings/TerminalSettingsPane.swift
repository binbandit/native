import SwiftUI

extension SettingsPane.ID {
    static let terminal = Self("terminal")
}

extension SettingsPane {
    /// Settings › Terminal, for `SettingsView(additionalPanes:)`.
    static func terminal(_ store: TerminalStore) -> SettingsPane {
        SettingsPane(
            id: .terminal,
            title: "Terminal",
            systemImage: "apple.terminal",
            group: .personal,
            order: 17,
            keywords: ["shell", "console", "ghostty", "pty", "zsh", "theme", "import"],
            searchEntries: {
                [
                    SettingsSearchEntry(
                        id: TerminalSettingsPage.ghosttyRow,
                        title: "Use my Ghostty settings",
                        description: "Load your Ghostty config's theme, fonts and key bindings.",
                        keywords: ["ghostty", "config", "theme"]
                    ),
                    SettingsSearchEntry(
                        id: TerminalSettingsPage.importRow, title: "Import from Ghostty", keywords: ["ghostty", "copy"]),
                    SettingsSearchEntry(
                        id: TerminalSettingsPage.cursorRow, title: "Cursor", keywords: ["blink", "caret"]),
                    SettingsSearchEntry(
                        id: TerminalSettingsPage.colorsRow, title: "Terminal colors", keywords: ["theme", "palette"],
                        plainly: .init(title: "Colors")),
                    SettingsSearchEntry(
                        id: TerminalSettingsPage.fontRow, title: "Font", keywords: ["typeface", "monospace", "family"]),
                    SettingsSearchEntry(id: TerminalSettingsPage.sizeRow, title: "Font size", keywords: ["text size"]),
                    SettingsSearchEntry(
                        id: TerminalSettingsPage.scrollbackRow,
                        title: "Scrollback",
                        description: "How many lines each terminal keeps.",
                        keywords: ["history", "lines", "buffer"], plainly: .scrollback),
                ]
            },
            content: { TerminalSettingsPage(store: store) }
        )
    }
}
