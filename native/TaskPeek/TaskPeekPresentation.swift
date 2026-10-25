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
    var showsAttentionList = false
    var answerFailure: String?
    var approvalAttempt = 0
    var isAnswering = false
    var isRecovering = false
}
