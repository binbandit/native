import Foundation
import NativeCommands
import Observation

extension CommandID {
    static let paletteShow: Self = "palette.show"
}

/// The command palette's state: whether it's open, what it acts on, and what the user ran
/// recently (listed first). What it lists comes from `sources`, which the app wires up: the
/// registry's commands, the tasks, the projects and the Settings pages. See `docs/commands.md`.
@MainActor
@Observable
final class CommandPalette {
    private static let recentsKey = "commandPalette.recents"
    private static let recentsLimit = 8

    private(set) var isPresented = false
    /// The window's state when the palette opened; commands run against it.
    private(set) var context = CommandContext()
    /// Item ids, most recent first.
    private(set) var recents: [CommandPaletteItem.ID]

    /// What the palette lists, in this order when nothing is typed.
    @ObservationIgnored var sources: [CommandPaletteSource] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recents = (defaults.stringArray(forKey: Self.recentsKey) ?? []).map(CommandPaletteItem.ID.init)
    }

    /// ⌘K: opens over the window the context came from, or closes it again.
    func toggle(in context: CommandContext) {
        if isPresented {
            dismiss()
        } else {
            self.context = context
            isPresented = true
        }
    }

    func dismiss() {
        isPresented = false
    }

    /// Everything the sources offer for `query`, recents first when it's empty.
    func items(for query: String) -> [CommandPaletteItem] {
        sources.flatMap { $0.items(query, context) }
    }

    /// Closes the palette, then runs the item, so focus is back in the window when it acts.
    func run(_ item: CommandPaletteItem) {
        dismiss()
        remember(item.id)
        item.run()
    }

    private func remember(_ id: CommandPaletteItem.ID) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        recents = Array(recents.prefix(Self.recentsLimit))
        defaults.set(recents.map(\.rawValue), forKey: Self.recentsKey)
    }
}

/// Something the palette lists or runs: a command, a task, a project or a Settings page.
struct CommandPaletteItem: Identifiable {
    /// Stable across launches ("command:session.archive", "task:…"), for recents.
    struct ID: RawRepresentable, Hashable, Sendable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// The section it's listed under.
    enum Kind: Int, CaseIterable, Comparable {
        case command, task, project, settings, query

        var title: String {
            switch self {
            case .command: "Commands"
            case .task: "Tasks"
            case .project: "Projects"
            case .settings: "Settings"
            case .query: "Search"
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let id: ID
    let kind: Kind
    let title: String
    /// Shown dimmer after the title: a task's project, a command's category.
    var subtitle: String?
    var systemImage: String
    var shortcut: KeyShortcut?
    /// More words that find it.
    var keywords: [String] = []
    /// For on/off commands, whether it's on: the row shows a checkmark.
    var isOn: Bool?
    let run: @MainActor () -> Void
}

/// A kind of thing the palette lists. Given the typed text and the window's context, it returns
/// its items; the palette ranks and groups them.
struct CommandPaletteSource {
    let items: @MainActor (_ query: String, _ context: CommandContext) -> [CommandPaletteItem]
}
