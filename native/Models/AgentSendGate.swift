import Foundation
import Observation

/// Why an agent's sessions can't take a message right now for reasons outside any one session: the
/// agent wants a sign-in (its runtime says so), or its account reached a usage limit, which the
/// Usage feature reports with `setUsageLimit(_:for:)`.
@Observable
final class AgentSendGate {
    /// Set by the app once its runtimes exist.
    @ObservationIgnored weak var runtimes: AgentRuntimes?
    private var usageLimits: [AgentDefinition.ID: String] = [:]
    /// Folders whose sessions take no new turn yet, with why, by their standardized `folderPath`.
    private var workspaceHolds: [String: String] = [:]

    /// The limit's message ("Claude's usage limit resets at 3:05 PM"), or nil once it's lifted.
    func setUsageLimit(_ message: String?, for agent: AgentDefinition.ID) {
        usageLimits[agent] = message
    }

    /// Holds the turns of every session in `folder` while something prepares it, such as the
    /// worktree's setup script: messages sent meanwhile queue. Nil lifts the hold; the caller then
    /// lets the queued messages go (`AppModel.holdTurns(in:because:)` does both).
    func setWorkspaceHold(_ reason: String?, for folder: URL) {
        workspaceHolds[folder.standardizedFileURL.folderPath] = reason
    }

    func workspaceHold(for folder: URL) -> String? {
        workspaceHolds.isEmpty ? nil : workspaceHolds[folder.standardizedFileURL.folderPath]
    }

    func block(for agent: AgentDefinition) -> SessionSendBlock? {
        if runtimes?[agent.id]?.needsSignIn == true {
            return .signInNeeded(agentName: agent.displayName)
        }
        return usageLimits[agent.id].map(SessionSendBlock.usageLimit)
    }
}

/// Why a session can't take a message now, for the composer to say instead of sending.
enum SessionSendBlock: Equatable {
    /// An agent's own subagent, which only its parent gives work to.
    case notAcceptingPrompts
    case disconnected(agentName: String)
    case signInNeeded(agentName: String)
    /// The usage limit's message.
    case usageLimit(String)

    var message: String {
        switch self {
        case .notAcceptingPrompts: "This subagent only takes work from the session that started it."
        case .disconnected(let agentName): "\(agentName) stopped running. Restart it from the sidebar to send."
        case .signInNeeded(let agentName): "Sign in to \(agentName) to send messages."
        case .usageLimit(let message): message
        }
    }
}
