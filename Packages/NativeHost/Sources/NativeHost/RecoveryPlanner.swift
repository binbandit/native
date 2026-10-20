import Foundation
import NativeHostProtocol

/// Decides what to do with a turn that was cut off, from facts alone, so every case is testable.
///
/// The rule follows Pi Durable's: never replay work blindly. If the agent's own transcript (its
/// `session/load` replay) has the prompt, the agent started on it, and whatever it did is in its
/// history; it's told the turn was interrupted and asked to check and continue. If the prompt isn't
/// there, it never arrived, so sending it again is safe. Tool calls are never re-run by Native.
enum RecoveryPlanner {
    enum Decision: Equatable {
        /// The prompt never reached the agent: send it again.
        case resend
        /// The agent had it: tell it the turn was interrupted and ask it to continue.
        case resume
        /// Recovery already failed this many times; stop so a crashing agent doesn't loop.
        case pause
    }

    /// How many times one turn is recovered before Native stops trying.
    static let maximumAttempts = 3

    static func decide(prompt: String, attempts: Int, replayedUserMessages: [String]) -> Decision {
        guard attempts < maximumAttempts else { return .pause }
        return agentReceived(prompt, replayedUserMessages: replayedUserMessages) ? .resume : .resend
    }

    /// How far back from the end of the agent's transcript a prompt still counts as its latest.
    /// Agents can record something after a prompt they were cut off on: Claude Code adds a
    /// "[Request interrupted by user]" user message when its process is killed (seen in E2E), which
    /// `SessionState` folds into the turn's stop, but other agents' additions may still count.
    static let recentUserMessages = 3

    /// Whether the prompt is among the agent's latest user messages. Agents may add context around a
    /// prompt when they store it, so containment counts. A false positive (the same text sent twice
    /// in a row, the second lost) only means a harmless "you were interrupted" message.
    static func agentReceived(_ prompt: String, replayedUserMessages: [String]) -> Bool {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return false }
        return replayedUserMessages.suffix(recentUserMessages).contains { message in
            let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return message == prompt || message.contains(prompt)
        }
    }

    /// What interrupted the host's previous run: a restart of the Mac if it has booted since, and
    /// otherwise the host itself stopping.
    static func cause(previousBoot: Date?, currentBoot: Date?) -> RecoveryNote.Cause {
        if let previousBoot, let currentBoot, abs(previousBoot.timeIntervalSince(currentBoot)) > 1 {
            return .systemRestarted
        }
        return .hostStopped
    }

    /// How the previous run ended, from what it left in the store: nil on a first run.
    static func ending(wasUpdate: Bool, cleanShutdown: String?, cause: RecoveryNote.Cause) -> ActivityEntry.RunEnding? {
        if wasUpdate { return .updated }
        switch cleanShutdown {
        case nil: return nil
        case "1": return .stopped
        default: return cause == .systemRestarted ? .systemRestarted : .crashed
        }
    }

    /// The message that tells an agent its turn was cut off. It reads as Native's, not the user's,
    /// and asks the agent to verify state rather than assume its last step completed.
    static func interruptionPrompt(cause: RecoveryNote.Cause) -> String {
        let reason =
            switch cause {
            case .agentStopped, .unknown: "your process stopped unexpectedly"
            case .agentRestarted: "the user restarted you"
            case .hostStopped: "Native's background process stopped unexpectedly"
            case .hostUpdated: "Native's background process restarted to update"
            case .systemRestarted: "the computer restarted"
            }
        return """
            [Native] Your previous turn was interrupted because \(reason). Whatever you were in the middle of \
            may not have finished, and the result of your last tool call may be missing. Check the current \
            state before you continue (for example, re-read files you were changing), then carry on with \
            the task. If it was already done, say so briefly.
            """
    }
}
