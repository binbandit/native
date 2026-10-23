extension SessionModel {
    func markTaskWellOutcomeReviewed(_ turnID: String?) {
        reviewedTaskWellTurnID = turnID
    }

    /// The well only leads to the task's existing request surface; it never sends an answer.
    func focusTaskAttention() {
        wantsComposerFocus = true
        if let call = permissionRequests.first {
            transcriptReveal = TranscriptReveal(itemID: "tool-\(call.id)")
        } else if taskStatus == .failed, let item = state.items.last {
            transcriptReveal = TranscriptReveal(itemID: item.id)
        }
    }
}
