#if DEBUG && NATIVE_SESSION_CHROME_WIP
/// A feature that puts something in the session screen's chrome. Each is a module the user turns
/// on and places; with every one off, the screen is the conversation and the composer.
enum SessionChromeTool: String, CaseIterable, Identifiable {
    case changes, terminal, run, agents, pullRequest, openIn

    var id: Self { self }

    var title: String {
        switch self {
        case .changes: "Changes"
        case .terminal: "Terminal"
        case .run: "Run"
        case .agents: "Subagents"
        case .pullRequest: "Pull Request"
        case .openIn: "Open In"
        }
    }

    var systemImage: String {
        switch self {
        case .changes: "plus.forwardslash.minus"
        case .terminal: "apple.terminal"
        case .run: "play"
        case .agents: "person.2"
        case .pullRequest: "arrow.triangle.branch"
        case .openIn: "arrow.up.forward.app"
        }
    }

    /// What it's for, in the tools editor.
    var summary: String {
        switch self {
        case .changes: "Review, commit and push what the agent changed"
        case .terminal: "Shells in the task's folder"
        case .run: "The project's actions: test, dev server, install"
        case .agents: "Subagents' conversations, while there are any"
        case .pullRequest: "The branch and its pull request"
        case .openIn: "Open the task's folder in your editor"
        }
    }

    /// False for a tool that acts at once rather than showing a pane.
    var hasPane: Bool { self != .openIn }

    /// The keys that show it today, for tooltips.
    var shortcut: String? {
        switch self {
        case .changes: "⇧⌘D"
        case .terminal: "⌃`"
        case .agents: "⌥⌘I"
        case .openIn: "⇧⌘O"
        case .run, .pullRequest: nil
        }
    }

    var help: String {
        shortcut.map { "\(title) (\($0))" } ?? title
    }
}
#endif
