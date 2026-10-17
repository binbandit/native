import ACP
import Foundation

extension SessionState {
    /// What the agent said to close its latest turn: its last run of messages after its last tool
    /// call since the user's last prompt. Narration between tool calls is left out because the
    /// session that delegated the task wants the outcome. Nil when it hasn't said anything yet.
    var latestReply: String? {
        var messages: [String] = []
        scan: for item in items.reversed() {
            switch item {
            case .message(let message) where message.role == .user: break scan
            case .message(let message) where message.role == .agent: messages.append(message.text)
            case .toolCall where !messages.isEmpty: break scan
            default: continue
            }
        }
        let reply = messages.reversed().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return reply.isEmpty ? nil : reply
    }

    /// The title of a tool call the agent is waiting on the user to approve.
    var awaitingApproval: String? {
        for case .toolCall(let call) in items where call.permission != nil {
            return call.title
        }
        return nil
    }

    /// The latest error the transcript noted, such as why a turn failed.
    var lastErrorNotice: String? {
        for case .notice(let notice) in items.reversed() where notice.isError {
            return notice.text
        }
        return nil
    }
}
