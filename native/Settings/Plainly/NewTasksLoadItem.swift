import Foundation
import TaskDefaults

struct NewTasksLoadItem: Identifiable {
    enum Control {
        case agentOwned, required, switchable(Bool), unavailable(String)
    }
    let id: String
    let name: String
    let source: String
    let kind: TaskContextBudget.Part.Kind
    var tokens: Int? = nil
    var included = true
    var control = Control.agentOwned
    var receipt: NewTasksSettingReceipt?
    var detail: String?
    /// For a file the agent reads from somewhere else (a project's own instructions): who reads it.
    var loadedBy: String?
    var needsAttention = false
    var setEnabled: ((Bool) -> Void)?
    var undo: (() -> Void)?
    var reset: (() -> Void)?
}
