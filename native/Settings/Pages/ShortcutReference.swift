import Foundation

/// The shortcuts in `docs/keyboard.md`, which is the source of truth: change a key there, then in
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
                        note: "While the agent works. Escape closes the slash-command list first.", keys: ["Esc", "⌘."]),
                    Shortcut(
                        id: "recall", title: "Recall the last prompt",
                        note: "In an empty composer. While the agent works, edits the last queued message.", keys: ["↑"]
                    ),
                ]),
            Group(
                title: "Slash commands",
                shortcuts: [
                    Shortcut(
                        id: "slash-open", title: "Open the command list", note: "At the start of the composer",
                        keys: ["/"]),
                    Shortcut(id: "slash-move", title: "Move the selection", keys: ["↑", "↓"]),
                    Shortcut(id: "slash-insert", title: "Insert the selected command", keys: ["↵", "Tab"]),
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
                title: "Sessions and navigation",
                shortcuts: [
                    Shortcut(id: "new-session", title: "New session", note: "With the last-used agent", keys: ["⌘N"]),
                    Shortcut(id: "new-session-with", title: "New session with…", note: "Pick the agent", keys: ["⌥⌘N"]),
                    Shortcut(id: "open-folder", title: "Open folder", keys: ["⌘O"]),
                    Shortcut(id: "focus-composer", title: "Focus the composer", keys: ["⌘L"]),
                    Shortcut(
                        id: "history", title: "Back / forward", note: "Through the sessions you've viewed",
                        keys: ["⌘[", "⌘]"]),
                    Shortcut(
                        id: "go-to-session", title: "Go to a session", note: "The Nth session in the sidebar",
                        keys: ["⌘1", "⌘9"], joiner: "–"),
                    Shortcut(id: "next-session", title: "Next / previous session", keys: ["⌃Tab", "⌃⇧Tab"]),
                    Shortcut(
                        id: "rename-session", title: "Rename the selected session",
                        note: "In the sidebar. Return commits, Escape cancels.", keys: ["↵"]),
                    Shortcut(id: "toggle-sidebar", title: "Show or hide the sidebar", keys: ["⌃⌘S"]),
                    Shortcut(
                        id: "move-item", title: "Move the selected project or session", note: "Up / down",
                        keys: ["⌥⌘↑", "⌥⌘↓"]),
                    Shortcut(id: "pull-requests", title: "Pull requests", keys: ["⌘⇧P"]),
                    Shortcut(id: "toggle-inspector", title: "Show or hide the subagent inspector", keys: ["⌥⌘I"]),
                    Shortcut(
                        id: "toggle-changes", title: "Show or hide the changes inspector",
                        note: "The task's uncommitted git changes", keys: ["⌘⇧D"]),
                ]),
            Group(
                title: "Session settings",
                shortcuts: [
                    Shortcut(id: "permission-mode", title: "Next permission mode", keys: ["⌘⇧M"]),
                    Shortcut(id: "model-picker", title: "Model picker", keys: ["⌘⇧E"]),
                    Shortcut(id: "goal", title: "Set or edit the session's goal", keys: ["⌥⌘G"]),
                    Shortcut(id: "workflow", title: "Run a workflow", keys: ["⌥⌘R"]),
                ]),
        ]
    }

    static func rowID(_ shortcut: Shortcut) -> SettingsRowID {
        SettingsRowID("shortcut.\(shortcut.id)")
    }
}
