import SwiftUI

/// An agent the home page offers to start a task with. The app builds these from the plugin
/// registry's agents and their runtimes; `ID` is whatever identifies an agent there.
public struct HomeAgent<ID: Hashable>: Identifiable {
    public enum Availability: Equatable {
        /// Ready for a new task.
        case available
        /// Still launching; it can't take a task yet.
        case starting
        /// A task is being started with it right now.
        case creatingTask
        /// It can't start tasks, with the status that says why, such as "Not installed" or
        /// "Limit reached · resets 3:05 PM".
        case unavailable(String)
    }

    public let id: ID
    public let name: String
    public let symbolName: String
    public let availability: Availability
    /// What gets an unavailable agent going again, such as signing in. The card offers it in
    /// place of starting a task, so it's never a dead button when something can be done.
    public let remedy: HomeAgentRemedy?
    /// The shortcut that starts a task with this agent in the chosen project, shown on its card.
    public let shortcut: KeyboardShortcut?

    public init(
        id: ID,
        name: String,
        symbolName: String,
        availability: Availability = .available,
        remedy: HomeAgentRemedy? = nil,
        shortcut: KeyboardShortcut? = nil
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.availability = availability
        self.remedy = remedy
        self.shortcut = shortcut
    }
}

/// The one action that fixes an agent that can't start tasks, titled as what it does: "Sign In to
/// Codex", "Check Again", "Restart Cursor".
public struct HomeAgentRemedy {
    public let title: String
    public let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}
