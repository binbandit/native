import Foundation
import Observation

@Observable
final class TaskPeekPresentation {
    struct Request: Identifiable {
        let id = UUID()
        let task: SessionKey
        let ask: TaskPeekAsk?
    }

    var homeIsVisible = false
    var request: Request?
    /// Pointer dismissal leaves focus with the clicked control; keyboard dismissal can return it.
    var restoresSidebarFocus = true
    var showsAttentionList = false
    var answerFailure: String?
    var approvalAttempt = 0
    var isAnswering = false
    var isRecovering = false
}
