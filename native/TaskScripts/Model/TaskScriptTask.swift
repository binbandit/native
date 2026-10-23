import Foundation

/// What Native knows about the task a script runs for, beyond its folder.
struct TaskScriptTask: Hashable, Sendable {
    var id: String?
    var title: String?
    /// The agent's id.
    var agent: String?
}
