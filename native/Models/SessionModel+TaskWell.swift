extension SessionModel {
    func markTaskWellOutcomeReviewed(_ turnID: String?) {
        reviewedTaskWellTurnID = turnID
    }

    /// The well only leads to the task's existing request surface; it never sends an answer.
    func focusTaskRequest() {
        wantsComposerFocus = true
        if let call = permissionRequests.first {
            transcriptReveal = TranscriptReveal(itemID: "tool-\(call.id)")
        }
    }
}
