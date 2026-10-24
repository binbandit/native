import Foundation
import Observation

@Observable
final class TaskPeekPresentation {
    struct Request: Identifiable {
        let id = UUID()
        let task: SessionKey
        let ask: TaskPeekAsk?
    }

    var request: Request?
    var showsAttentionList = false
    var isAnswering = false
    var isRecovering = false
}
