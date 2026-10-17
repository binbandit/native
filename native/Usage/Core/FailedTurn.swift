import ACP
import Foundation

/// A turn that ended in an error, read for what a usage limit left undone.
struct FailedTurn {
    let prompt: String
    /// What the turn added to the transcript after the prompt.
    let items: [TranscriptItem]

    /// The agent's last words in the turn, where adapters put the provider's limit message.
    var agentText: String? {
        items.lazy.reversed().compactMap { item -> String? in
            guard case .message(let message) = item, message.role == .agent else { return nil }
            return message.text
        }.first
    }

    /// Whether the agent got anything done before the turn failed. The provider's own limit
    /// message doesn't count: adapters send it as an agent message.
    var didProgress: Bool {
        items.contains { item in
            switch item {
            case .toolCall, .subagent, .sessionMessage: true
            case .message(let message):
                message.role != .user
                    && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !UsageLimitHit.isLimitMessage(message.text)
            case .notice: false
            }
        }
    }

    /// A refused prompt goes out again as written; a turn cut off midway is asked to carry on.
    var work: LimitedWork {
        didProgress ? .interruptedTurn : .unsentPrompt(prompt)
    }
}
