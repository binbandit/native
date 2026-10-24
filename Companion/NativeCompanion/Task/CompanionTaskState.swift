import NativeHostProtocol
import Observation

/// A task's unsent work and reading location belong to the task, not its current column.
@Observable
final class CompanionTaskState {
    var draft = ""
    var behavior = PromptBehavior.queue
    var notSent: String?
    var isSending = false
    var delivered: String?
    var visibleItemID: String?
}
