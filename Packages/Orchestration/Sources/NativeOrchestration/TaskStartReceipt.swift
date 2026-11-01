import Foundation

/// The creation response is stable even after the child finishes or receives another message.
public struct TaskStartReceipt: Sendable {
    public var task: OrchestrationTask
    public var snapshot: TaskSnapshot?

    public init(task: OrchestrationTask, snapshot: TaskSnapshot?) {
        self.task = task
        self.snapshot = snapshot
    }
}
