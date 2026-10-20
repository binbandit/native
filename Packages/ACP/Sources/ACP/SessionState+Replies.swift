import Foundation

// What another session (or a workflow) wants to know of a transcript: how the latest turn ended up.
extension SessionState {
    /// What the agent said to close its latest turn: its last run of messages after its last tool
    /// call since the last prompt. Narration between tool calls is left out because whoever handed
    /// over the work wants the outcome. Nil when it hasn't said anything yet.
    public var latestReply: String? {
        var messages: [String] = []
        scan: for item in items.reversed() {
            switch item {
            // A message from another session starts a turn without a user message, so it bounds
            // the reply too; otherwise the previous turn's reply would pass for this one's.
            case .message(let message) where message.role == .user: break scan
            case .sessionMessage: break scan
            case .message(let message) where message.role == .agent: messages.append(message.text)
            case .toolCall where !messages.isEmpty: break scan
            default: continue
            }
        }
        let reply = messages.reversed().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return reply.isEmpty ? nil : reply
    }

    /// The title of a tool call the agent is waiting on the user to approve.
    public var awaitingApproval: String? {
        for case .toolCall(let call) in items where call.permission != nil {
            return call.title
        }
        return nil
    }

    /// The latest error the transcript noted, such as why a turn failed.
    public var lastErrorNotice: String? {
        for case .notice(let notice) in items.reversed() where notice.isError {
            return notice.text
        }
        return nil
    }
}
