import Foundation

/// Where "Ask an Agent" sends lines of a pull request.
enum GitHubAgentDestination: Sendable, Hashable {
    /// A new task in a checkout of the pull request's branch.
    case newTask
    /// The task on screen, as its next message.
    case currentTask
}
