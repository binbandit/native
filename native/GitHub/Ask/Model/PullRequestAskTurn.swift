import ACP
import Foundation
import GitHub

/// One question and its answer, as the panel shows it: the question as the user typed it (the
/// context Native framed it with read back off), the agent's tool work, requests waiting on the
/// user, the answer, and how the turn ended.
struct PullRequestAskTurn: Identifiable {
    let id: String
    /// Nil for a turn that didn't start with the user's question (an agent's own preamble).
    var question: String?
    /// What the question carried besides itself: the context, or the context again after new commits.
    var carried: PullRequestAskPrompt.Message.Kind?
    /// Tool work, in order, as transcript rows (runs of reads folded together).
    var activity: [TranscriptRow] = []
    var summary: TurnSummary
    /// Tool calls waiting for the user's permission.
    var requests: [ToolCallState] = []
    /// What the agent said before its last tool call ("I'll read the diff first"): progress, not
    /// the answer, so it stays out of a drafted comment.
    var commentary: [String] = []
    /// The agent's reply after its tool work, its messages joined.
    var answer = ""
    var notices: [TranscriptNotice] = []
    var stopReason: StopReason?
    /// What the agent is doing right now, while this is the running turn.
    var current: String?
    var isRunning = false

    /// The conversation's turns, oldest first. Only the last one can be running.
    static func turns(of session: SessionModel) -> [PullRequestAskTurn] {
        let state = session.state
        let turns = state.turns
        return turns.enumerated().map { position, turn in
            let items = Array(state.items[turn.items])
            let isRunning = position == turns.count - 1 && session.phase == .prompting
            return PullRequestAskTurn(items: items, id: turn.id, stopReason: turn.stopReason, isRunning: isRunning)
        }
    }

    private init(items: [TranscriptItem], id: String, stopReason: StopReason?, isRunning: Bool) {
        self.id = id
        self.stopReason = stopReason
        self.isRunning = isRunning
        summary = TurnSummary(items: items, stopReason: stopReason)
        var work: [TranscriptItem] = []
        var replies: [String] = []
        let lastToolCall = items.lastIndex { if case .toolCall = $0 { true } else { false } }
        for (index, item) in items.enumerated() {
            switch item {
            case .message(let message) where message.role == .user:
                // Follow-ups are queued, never steered in, so a turn has one question.
                if question == nil {
                    let framed = PullRequestAskPrompt.message(message.text)
                    question = framed?.question ?? message.text
                    carried = framed?.kind
                }
            case .message(let message) where message.role == .agent:
                if let lastToolCall, index < lastToolCall {
                    commentary.append(message.text)
                } else {
                    replies.append(message.text)
                }
            case .message:
                work.append(item)
            case .toolCall(let call) where call.permission != nil:
                requests.append(call)
            case .toolCall:
                work.append(item)
            case .notice(let notice):
                notices.append(notice)
            case .subagent, .sessionMessage:
                work.append(item)
            }
        }
        commentary = commentary.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        answer = replies.filter { !$0.isEmpty }.joined(separator: "\n\n")
        // Reasoning stays out of the panel; only tool work folds into the activity line.
        activity = TranscriptRow.rows(from: work.filter { if case .message = $0 { false } else { true } })
        if isRunning {
            // A turn without a question is Native asking the agent to finish after it stopped.
            current = Self.current(in: items) ?? (question == nil && answer.isEmpty ? "Picking up where it stopped" : nil)
        }
    }

    /// The agent's latest step, in plain words, for the status line; nil while the answer itself
    /// is streaming, which shows for itself.
    private static func current(in items: [TranscriptItem]) -> String? {
        switch items.last {
        case .toolCall(let call) where call.permission != nil: "Waiting for your permission"
        case .toolCall(let call): call.title
        case .message(let message) where message.role == .thought: "Thinking"
        case .message(let message) where message.role == .agent: nil
        case .message(let message) where message.role == .user: "Reading the pull request"
        default: nil
        }
    }
}
