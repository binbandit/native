import Foundation

/// One of the task's rows under the settings popover's choices (Mode, Goal, MCP servers, Web search,
/// the agent's own settings): a label, its value, and what it opens. The popover draws every row the
/// same way and walks them with the keyboard; the control that builds them knows what they do.
struct ComposerSettingsTaskRow: Identifiable {
    /// A choice a menu row offers, in the menu and on its page.
    struct Choice: Identifiable {
        let id: String
        let name: String
        var summary: String?
        /// Choices with the same section are grouped under it ("Your modes").
        var section: String?
        let isCurrent: Bool
    }

    enum Kind {
        /// A menu of choices, with commands after them ("Edit Modes…").
        case menu([Choice], commands: [Command])
        /// A page that opens in place (Goal, MCP servers).
        case page
        case toggle(isOn: Bool)
        /// Something said, not changed ("Unavailable offline").
        case note
    }

    struct Command: Identifiable {
        let title: String
        let action: () -> Void
        var id: String { title }
    }

    let id: String
    let title: String
    var value: String
    /// Draws the value quieter, for "None".
    var isValueQuiet = false
    /// A failure said in red after the value ("1 failed").
    var failure: String?
    let kind: Kind
    /// Opens the page, flips the switch, or picks a choice by id.
    let perform: (String?) -> Void

    var accessibilityHint: String {
        switch kind {
        case .menu: "Opens a menu"
        case .page: "Opens a page"
        case .toggle, .note: ""
        }
    }
}
