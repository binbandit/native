import Foundation

/// The message Native sends an agent whose turn was cut off (a crash, a restart), asking it to check
/// what it was doing and carry on. Agents record it like any prompt and replay it with their history;
/// the transcript shows it for what it is, Native's word to the agent, never as something the user
/// typed. The host builds it from here, so what it sends and what the transcript recognizes agree.
public struct RecoveryPrompt: Hashable, Sendable {
    /// Why the turn was cut off, as the agent reads it.
    public enum Reason: String, CaseIterable, Sendable {
        case agentStopped = "your process stopped unexpectedly"
        case agentRestarted = "the user restarted you"
        case hostStopped = "Native's background process stopped unexpectedly"
        case hostUpdated = "Native's background process restarted to update"
        case systemRestarted = "the computer restarted"

        /// The same reason, as the user reads it.
        var forUser: String {
            switch self {
            case .agentStopped: "the agent stopped unexpectedly"
            case .agentRestarted: "you restarted the agent"
            case .hostStopped: "Native's background host stopped unexpectedly"
            case .hostUpdated: "Native's background host restarted to update"
            case .systemRestarted: "your Mac restarted"
            }
        }
    }

    /// Nil for a prompt whose reason this version doesn't know.
    public var reason: Reason?

    public init(reason: Reason) {
        self.reason = reason
    }

    /// Recognizes Native's prompt among the user messages an agent replays.
    init?(replayed text: String) {
        guard text.hasPrefix(Self.opening) else { return nil }
        reason = Reason.allCases.first { text.hasPrefix("\(Self.opening) because \($0.rawValue).") }
    }

    private static let opening = "[Native] Your previous turn was interrupted"

    /// What Native sends the agent. It reads as Native's, not the user's, and asks the agent to verify
    /// state rather than assume its last step completed.
    public var text: String {
        """
        \(Self.opening) because \((reason ?? .agentStopped).rawValue). Whatever you were in the middle of \
        may not have finished, and the result of your last tool call may be missing. Check the current \
        state before you continue (for example, re-read files you were changing), then carry on with \
        the task. If it was already done, say so briefly.
        """
    }

    /// What the transcript says in its place.
    var notice: String {
        let cause = reason.map { " because \($0.forUser)" } ?? ""
        return "This turn was interrupted\(cause). Native asked the agent to pick up where it left off."
    }
}
