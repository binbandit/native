import Foundation

extension SessionModel {
    /// Empty transcript alone is insufficient: a first message can be queued or in flight.
    var canChangeWorkspace: Bool {
        origin == .user && !isSubagent && !isEarlierConversation && !hasStarted
            && services.earlierConversations.conversation(before: key) == nil
            && !hasSubmittedPrompt && !hasQueuedPrompts && !isChangingWorkspace && !isWorkspaceReplaced
            && !isChangingAgent && !isRunningHiddenCommand && !isRetryScheduled
            && !isRestoringHistory && phase == .idle && !needsApproval
    }

    func requestWorkspaceChange() {
        guard canChangeWorkspace else { return }
        isWorkspacePickerRequested = true
    }
}
