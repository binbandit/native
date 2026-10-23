import ACP

extension SessionModel {
    func markTaskWellOutcomeReviewed(_ turnID: String?) {
        reviewedTaskWellTurnID = turnID
    }

    /// The well only leads to the task's existing request surface; it never sends an answer.
    @discardableResult func focusTaskAttention() -> SessionID? {
        wantsComposerFocus = true
        if pendingQuestion != nil { return nil }
        if let call = permissionRequests.first {
            transcriptReveal = TranscriptReveal(itemID: "tool-\(call.id)")
        } else if let child = children.values.first(where: { $0.wait != nil || $0.needsApproval }) {
            child.focusTaskAttention()
            return child.id
        } else if let child = state.subagents.first(where: { $0.workState == .requiresAction }) {
            return child.id
        } else if taskStatus == .failed, let item = state.items.last {
            transcriptReveal = TranscriptReveal(itemID: item.id)
        }
        return nil
    }
}
