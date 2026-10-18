/// Shortcuts no command can take: macOS's standard ones (Copy, Quit, …), which stay outside the
/// registry, and the keys Native's views answer themselves (`docs/keyboard.md`).
public enum ReservedShortcuts {
    /// Why `shortcut` can't be assigned, or nil when it can.
    public static func rejection(for shortcut: KeyShortcut) -> Rejection? {
        if let owner = owners[shortcut] {
            return .reserved(owner)
        }
        guard shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.control) else {
            return .needsCommandOrControl
        }
        return nil
    }

    public enum Rejection: Equatable, Sendable {
        /// Without ⌘ or ⌃ it would get in the way of typing.
        case needsCommandOrControl
        /// What already answers it, such as "Copy".
        case reserved(String)
    }

    static let owners: [KeyShortcut: String] = table.reduce(into: [:]) { owners, entry in
        if let shortcut = KeyShortcut(entry.key) {
            owners[shortcut] = entry.value
        }
    }

    /// Every entry must parse (a test checks).
    static let table: [String: String] = [
        // The app, Edit and Window menus macOS provides.
        "⌘Q": "Quit",
        "⌘H": "Hide Native",
        "⌥⌘H": "Hide Others",
        "⌘W": "Close Window",
        "⌘,": "Settings",
        "⌘M": "Minimize",
        "⌘Z": "Undo",
        "⇧⌘Z": "Redo",
        "⌘X": "Cut",
        "⌘C": "Copy",
        "⌘V": "Paste",
        "⌥⇧⌘V": "Paste and Match Style",
        "⌘A": "Select All",
        "⌘F": "Find",
        "⌘G": "Find Next",
        "⇧⌘G": "Find Previous",
        "⌃⌘F": "Enter Full Screen",
        "⌃⌘Space": "Emoji & Symbols",
        "⇧⌘/": "Help",
        "⌘`": "Move focus to the next window",
        "⌘Tab": "Switch apps",
        "⌘Space": "Spotlight",
        // Keys Native's own views answer.
        "⌘Y": "Allow once on a permission request",
        "⌥⌘Y": "Allow always on a permission request",
        "⇧⌘⌫": "Reject a permission request",
        "⌘↩": "Confirm a sheet or commit",
    ]
}
