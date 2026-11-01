import NativeCommands
import SwiftUI

/// One user action, defined once: the menu bar places it, the command palette runs it, and
/// Settings ▸ Keyboard Shortcuts rebinds it. Its default shortcut comes from `DefaultShortcuts`
/// (mirroring `docs/keyboard.md`), and the user's binding from `CommandRegistry`.
///
/// Features build their commands next to their own code and the app registers them; `perform`
/// calls a model method, so every client can drive the same action. See `docs/commands.md`.
struct NativeCommand: Identifiable {
    typealias ID = CommandID

    let id: ID
    /// The name Settings and the palette show, such as "Archive Task".
    let title: String
    let category: CommandCategory
    var systemImage: String?
    /// More words that find it in the palette and in Settings.
    var keywords: [String] = []
    /// The menu's title right now, where it reads the state ("Show Sidebar" or "Hide Sidebar").
    var menuTitle: (@MainActor (CommandContext) -> String)?
    /// For commands that switch something on and off, whether it's on: the menu shows a checkmark.
    var isOn: (@MainActor (CommandContext) -> Bool)?
    /// Whether the palette offers it. Commands that only make sense from the menu bar (going to the
    /// Nth session, say) set this to false; they still have a shortcut.
    var showsInPalette = true
    /// Experiments keep their shortcut settings hidden until their gate is enabled.
    var showsInSettings: @MainActor () -> Bool = { true }
    /// Whether it can run now. The menu disables it, the palette leaves it out, and its shortcut
    /// goes to whatever else wants the key.
    var isAvailable: @MainActor (CommandContext) -> Bool = { _ in true }
    let perform: @MainActor (CommandContext) -> Void
    /// A command that takes the palette's text, such as searching transcripts for it: the palette
    /// offers it as "<title> for “text”" whenever there's text.
    var performWithQuery: (@MainActor (String, CommandContext) -> Void)?

    init(
        _ id: ID,
        title: String,
        category: CommandCategory,
        systemImage: String? = nil,
        keywords: [String] = [],
        perform: @escaping @MainActor (CommandContext) -> Void
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.systemImage = systemImage
        self.keywords = keywords
        self.perform = perform
    }

    /// Fluent setters, so a definition reads top to bottom.
    func available(_ isAvailable: @escaping @MainActor (CommandContext) -> Bool) -> Self {
        var command = self
        command.isAvailable = isAvailable
        return command
    }

    /// Unavailable while something else claims its shortcut, so the key goes there instead.
    func stepsAside(when isClaimed: @escaping @MainActor (CommandContext) -> Bool) -> Self {
        var command = self
        let isAvailable = isAvailable
        command.isAvailable = { isAvailable($0) && !isClaimed($0) }
        return command
    }

    func menuTitle(_ title: @escaping @MainActor (CommandContext) -> String) -> Self {
        var command = self
        command.menuTitle = title
        return command
    }

    func toggles(_ isOn: @escaping @MainActor (CommandContext) -> Bool) -> Self {
        var command = self
        command.isOn = isOn
        return command
    }

    func hiddenFromPalette() -> Self {
        var command = self
        command.showsInPalette = false
        return command
    }

    func shownInSettings(_ predicate: @escaping @MainActor () -> Bool) -> Self {
        var command = self
        command.showsInSettings = predicate
        return command
    }

    func takesQuery(_ perform: @escaping @MainActor (String, CommandContext) -> Void) -> Self {
        var command = self
        command.performWithQuery = perform
        return command
    }
}

/// Where a command sits in Settings ▸ Keyboard Shortcuts, in this order.
enum CommandCategory: Int, CaseIterable, Comparable, Identifiable {
    case general
    case tasks
    case navigation
    case composer
    case view
    case terminal
    /// Running a project's actions (`docs/actions.md`).
    case actions
    /// Commands plugins add.
    case plugins

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .tasks: "Tasks"
        case .navigation: "Navigation"
        case .composer: "Composer and agent"
        case .view: "View"
        case .terminal: "Terminal"
        case .actions: "Project actions"
        case .plugins: "Plugins"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
