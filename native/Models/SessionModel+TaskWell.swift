import ACP
import Foundation

extension SessionModel {
    var taskWellAttentionSince: Date? {
        if let question = pendingQuestion { return question.requestedAt }
        if let permission = permissionRequests.first?.permission { return permission.requestedAt }
        return children.values.lazy.compactMap(\.taskWellAttentionSince).first
    }

    func markTaskWellOutcomeReviewed(_ turnID: String?) {
        reviewedTaskWellTurnID = turnID
    }

    /// The well only leads to the task's existing request surface; it never sends an answer.
    @discardableResult func focusTaskAttention() -> SessionID? {
        if pendingQuestion != nil {
            wantsComposerFocus = true
            return nil
        }
        if let call = permissionRequests.first {
            wantsComposerFocus = true
            transcriptReveal = TranscriptReveal(itemID: "tool-\(call.id)")
        } else if let child = children.values.first(where: { $0.wait != nil || $0.needsApproval }) {
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
