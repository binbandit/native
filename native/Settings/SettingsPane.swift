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

    /// The nav's sections, in order (the reference app's "Personal", "Agents & environment", "More").
    /// Empty groups are hidden.
    enum Group: Int, CaseIterable, Comparable {
        case personal
        case agents
        /// Everything Native adds beyond the agents themselves, each switchable (Native starts
        /// minimal; see `docs/decisions.md`).
        case extensions
        case more

        var title: String {
            switch self {
            case .personal: "Personal"
            case .agents: "Agents"
            case .extensions: "Extensions"
            case .more: "More"
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
    /// Position within the group. Built-in panes use multiples of 10 so others can go between.
    let order: Int
    /// More words that find the pane in search, such as "dock" for Appearance.
    let keywords: [String]
    /// The rows search can jump to; each id must be a `settingsRevealTarget` on the page.
    let searchEntries: @MainActor () -> [SettingsSearchEntry]
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
        var panes: [SettingsPane] = [
            .general, .keyboardShortcuts, .agents(registry: registry), .extensions(registry: registry),
        ]
        #if os(macOS)
        // The app icon is the Dock's; iPadOS sets icons another way.
        panes.append(.appearance)
        #endif
        return panes
    }
}
