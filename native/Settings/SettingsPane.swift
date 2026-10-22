import SwiftUI

/// A page in the Settings window. Settings' own pages and other features' pages are all values of
/// this type: a feature builds its pane next to its own code and the app passes it to
/// `SettingsScreen(pane:additionalPanes:)`, so adding a page never touches Settings.
struct SettingsPane: Identifiable {
    struct ID: Hashable, Sendable {
        let rawValue: String

        init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// The nav's sections, in order ("Personal", "Agents", "Extensions", "More", "Projects").
    /// Empty groups are hidden.
    enum Group: Int, CaseIterable, Comparable {
        case personal
        case agents
        /// Everything Native adds beyond the agents themselves, each switchable (Native starts
        /// minimal; see `docs/decisions.md`).
        case extensions
        case more
        /// A page per open project, after everything that applies to all of them.
        case projects

        var title: String {
            switch self {
            case .personal: "Personal"
            case .agents: "Agents"
            case .extensions: "Extensions"
            case .more: "More"
            case .projects: "Projects"
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let id: ID
    let title: String
    let systemImage: String
    let group: Group
    /// Position within the group. Each built-in pane has a distinct value, with gaps for additions.
    let order: Int
    /// More words that find the pane in search, such as "dock" for Appearance.
    let keywords: [String]
    /// The rows search can jump to; each id must be a `settingsRevealTarget` on the page.
    let searchEntries: @MainActor () -> [SettingsSearchEntry]
    /// What leads its nav row instead of `systemImage`, such as a project's own icon.
    private(set) var navIcon: (@MainActor () -> AnyView)?
    private let content: @MainActor () -> AnyView

    init<Content: View>(
        id: ID,
        title: String,
        systemImage: String,
        group: Group,
        order: Int,
        keywords: [String] = [],
        searchEntries: @escaping @MainActor () -> [SettingsSearchEntry] = { [] },
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.group = group
        self.order = order
        self.keywords = keywords
        self.searchEntries = searchEntries
        // Panes come from different features, so their views can only share a type erased.
        self.content = { AnyView(content()) }
    }

    func makeContent() -> AnyView {
        content()
    }

    /// The pane with `icon` leading its nav row, 16pt square.
    func navIcon<Icon: View>(@ViewBuilder _ icon: @escaping @MainActor () -> Icon) -> Self {
        var pane = self
        pane.navIcon = { AnyView(icon()) }
        return pane
    }
}

/// A setting search can find and jump to.
struct SettingsSearchEntry {
    let id: SettingsRowID
    let title: String
    var description = ""
    var keywords: [String] = []
}

/// Where a row lives on its page, for search to scroll to and flash.
struct SettingsRowID: Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SettingsPane {
    /// The panes Settings itself provides. `registry` is the host's: a client of several hosts
    /// passes the one the pages should describe.
    static func builtIn(registry: PluginRegistry) -> [SettingsPane] {
        [
            .general, .keyboardShortcuts, .agents(registry: registry), .extensions(registry: registry), .appearance,
            .privacy,
        ]
    }
}
