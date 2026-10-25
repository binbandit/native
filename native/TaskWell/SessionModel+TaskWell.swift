import ACP
import Foundation

extension SessionModel {
    /// The ask the well speaks for: the task's oldest, wherever in it it waits, which is the one its
    /// sidebar row and Peek show (`TaskPeekAsk`), so the three never disagree about what's waiting
    /// or since when.
    var taskWellAsk: TaskPeekAsk? {
        TaskPeekAsk.requests(in: self, task: key).first
    }

    func markTaskWellOutcomeReviewed(_ turnID: String?) {
        reviewedTaskWellTurnID = turnID
    }

    /// The well only leads to the task's existing request surface; it never sends an answer.
    @discardableResult func focusTaskAttention() -> SessionID? {
        if let ask = taskWellAsk {
            ask.session.wantsComposerFocus = true
            if case .permission(let call) = ask.content {
                ask.session.transcriptReveal = TranscriptReveal(itemID: "tool-\(call.id)")
            }
            return ask.session === self ? nil : ask.session.id
        }
        // A subagent said it's blocked on the user before its request reached the task.
        if let child = children.values.first(where: \.needsApproval) {
            return child.focusTaskAttention() ?? child.id
        } else if let child = state.subagents.first(where: { $0.workState == .requiresAction }) {
            return child.id
        } else if taskStatus == .failed, let item = state.items.last {
            wantsComposerFocus = true
            transcriptReveal = TranscriptReveal(itemID: item.id)
        }
        return nil
    }

    /// A wait can come from any descendant. Keep its roster identity and live session together
    /// so opening the well's request reveals the actual owner, not just its immediate parent.
    func taskWellSubagent(_ id: SessionID) -> (subagent: SubagentState, child: SessionModel?)? {
        if let subagent = state.subagents.first(where: { $0.id == id }) {
            return (subagent, child(id))
        }
        return children.values.lazy.compactMap { $0.taskWellSubagent(id) }.first
    }
}
