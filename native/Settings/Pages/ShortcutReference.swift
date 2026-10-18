import Foundation

/// The keys views answer themselves, which can't be changed (the registry's commands are listed
/// from the registry). `docs/keyboard.md` is the source of truth: change a key there, then in
/// code, then here.
enum ShortcutReference {
    struct Group: Identifiable {
        let title: String
        var note: String?
        let shortcuts: [Shortcut]

        var id: String { title }
    }

    struct Shortcut: Identifiable {
        let id: String
        let title: String
        var note: String?
        /// Each entry is one keycap, such as "⌘⇧M" or "⇧↵" ("↵" is Return).
        let keys: [String]
        /// Text between keycaps when they form a range ("–"); alternatives sit side by side.
        var joiner: String?

        /// Spoken key names for search ("command", "return").
        var keywords: [String] {
            let names: [Character: String] = [
                "⌘": "command cmd", "⌥": "option alt", "⌃": "control ctrl", "⇧": "shift", "↵": "return enter",
                "⌫": "delete backspace", "↑": "up arrow", "↓": "down arrow",
            ]
            return keys + keys.flatMap { $0.compactMap { names[$0] } }
        }
    }

    /// Return and ⌘Return describe the user's follow-up behavior, so the groups depend on it.
    static func groups(followUp: FollowUpBehavior) -> [Group] {
        [
            Group(
                title: "Sending",
                shortcuts: [
                    Shortcut(id: "send", title: "Send", note: "\(followUp.title)s while the agent works", keys: ["↵"]),
                    Shortcut(
                        id: "send-other", title: "Send", note: "\(followUp.opposite.title)s while the agent works",
                        keys: ["⌘↵"]),
                    Shortcut(id: "new-line", title: "New line", keys: ["⇧↵", "⌥↵"]),
                    Shortcut(
                        id: "stop", title: "Stop the turn",
                        note: "While the agent works. Escape closes the slash-command list first.", keys: ["Esc"]),
                    Shortcut(
                        id: "recall", title: "Recall the last prompt",
                        note: "In an empty composer. While the agent works, edits the last queued message.", keys: ["↑"]
                    ),
                ]),
            Group(
                title: "Agent questions", note: "When an agent asks structured questions, the card takes focus.",
                shortcuts: [
                    Shortcut(id: "question-pick", title: "Pick that option", keys: ["1", "9"], joiner: "–"),
                    Shortcut(id: "question-move", title: "Move between options", keys: ["↑", "↓"]),
                    Shortcut(id: "question-space", title: "Pick the highlighted option", keys: ["Space"]),
                    Shortcut(
                        id: "question-next", title: "Next question", note: "Sends the answers after the last",
                        keys: ["↵"]),
                    Shortcut(
                        id: "question-tab", title: "Move between the card, its field and the composer",
                        keys: ["Tab", "⇧Tab"]),
                ]),
            Group(
                title: "Slash commands and file mentions",
                shortcuts: [
                    Shortcut(
                        id: "slash-open", title: "Open the command list", note: "At the start of the composer",
                        keys: ["/"]),
                    Shortcut(
                        id: "mention-open", title: "Open the file list", note: "At the start of a word", keys: ["@"]),
                    Shortcut(id: "slash-move", title: "Move the selection", keys: ["↑", "↓"]),
                    Shortcut(id: "slash-insert", title: "Insert the selection", keys: ["↵", "Tab"]),
                    Shortcut(id: "slash-close", title: "Close the list", keys: ["Esc"]),
                ]),
            Group(
                title: "Permission requests",
                note:
                    "The oldest pending request in the visible session answers these: a tool's permission request or a workflow step waiting for approval.",
                shortcuts: [
                    Shortcut(
                        id: "allow-once", title: "Allow once", note: "Also approves a workflow step", keys: ["⌘Y"]),
                    Shortcut(
                        id: "allow-always", title: "Allow always", note: "When the agent offers it", keys: ["⌥⌘Y"]),
                    Shortcut(id: "reject", title: "Reject", keys: ["⌘⇧⌫"]),
                ]),
            Group(
                title: "Git",
                shortcuts: [
                    Shortcut(
                        id: "commit", title: "Commit the selected files", note: "In the commit popover", keys: ["⌘↵"]),
                    Shortcut(
                        id: "smart-commit", title: "Commit the planned groups", note: "In Smart Commit", keys: ["⌘↵"]),
                    Shortcut(
                        id: "setup-script", title: "Save the setup script", note: "In Settings ▸ Git", keys: ["⌘↵"]),
                ]),
            Group(
                title: "Sidebar and palette",
                shortcuts: [
                    Shortcut(
                        id: "rename-session", title: "Rename the selected session",
                        note: "In the sidebar. Return commits, Escape cancels.", keys: ["↵"]),
                    Shortcut(
                        id: "palette-move", title: "Move through the palette", note: "Return runs", keys: ["↑", "↓"]),
                    Shortcut(id: "palette-close", title: "Close the palette", keys: ["Esc"]),
                ]),
            Group(
                title: "Settings",
                shortcuts: [
                    Shortcut(id: "settings-open", title: "Open or close Settings", keys: ["⌘,"]),
                    Shortcut(id: "settings-search", title: "Search settings", keys: ["⌘F"]),
                    Shortcut(
                        id: "settings-results", title: "Move through the results", note: "Return opens one",
                        keys: ["↑", "↓"]),
                    Shortcut(
                        id: "settings-close", title: "Close Settings", note: "Escape clears the search first",
                        keys: ["Esc"]),
                ]),
            Group(
                title: "Inside a terminal",
                shortcuts: [
                    Shortcut(id: "terminal-clear", title: "Clear the screen and scrollback", keys: ["⌘K"]),
                    Shortcut(id: "terminal-scroll-ends", title: "Scroll to the top / bottom", keys: ["⌘Home", "⌘End"]),
                    Shortcut(id: "terminal-page", title: "Scroll by a page", keys: ["⌘PageUp", "⌘PageDown"]),
                    Shortcut(id: "terminal-prompts", title: "Previous / next prompt", keys: ["⌘⇧↑", "⌘⇧↓"]),
                ]),
        ]
    }

    static func rowID(_ shortcut: Shortcut) -> SettingsRowID {
        SettingsRowID("shortcut.\(shortcut.id)")
    }
}
