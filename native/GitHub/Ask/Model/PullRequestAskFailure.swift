import Foundation
import GitHub

/// Why a question about a pull request couldn't go out. The panel shows each with what Native did
/// and the one action that fixes it; the question waits in the composer meanwhile.
enum PullRequestAskFailure: Error {
    /// No agent is installed to ask.
    case noAgent
    /// The agent can't start: its command is missing, or it stopped.
    case agentUnavailable(agent: AgentDefinition.ID, name: String, guidance: String?)
    /// The agent wants the user to sign in before it starts a session.
    case signInRequired(agent: AgentDefinition.ID, name: String)
    /// gh couldn't read the pull request.
    case gitHub(GitHubError)
    /// The agent's folder couldn't be written.
    case workspace(String)
    /// The agent refused the session.
    case startFailed(name: String, message: String)
    /// The earlier conversation couldn't be reopened.
    case reopenFailed(name: String, message: String)
}
