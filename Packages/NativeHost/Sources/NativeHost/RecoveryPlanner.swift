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

    /// Whether the agent's transcript ends with the prompt as its latest user message. Agents may
    /// add context around a prompt when they store it, so containment counts.
    static func agentReceived(_ prompt: String, replayedUserMessages: [String]) -> Bool {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = replayedUserMessages.last?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else {
            return false
        }
        return last == prompt || last.contains(prompt)
    }

    /// What interrupted the host's previous run: a restart of the Mac if it has booted since, and
    /// otherwise the host itself stopping.
    static func cause(previousBoot: Date?, currentBoot: Date?) -> RecoveryNote.Cause {
        if let previousBoot, let currentBoot, abs(previousBoot.timeIntervalSince(currentBoot)) > 1 {
            return .systemRestarted
        }
        return .hostStopped
    }

    /// The message that tells an agent its turn was cut off. It reads as Native's, not the user's,
    /// and asks the agent to verify state rather than assume its last step completed.
    static func interruptionPrompt(cause: RecoveryNote.Cause) -> String {
        let reason = switch cause {
        case .agentStopped, .unknown: "your process stopped unexpectedly"
        case .hostStopped: "Native's background process stopped unexpectedly"
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
