import Foundation

/// What the status bar's own items need from the app, so they depend on this rather than on the
/// app model's internals. `AppModel` conforms in `AppModel+StatusBarSource.swift`.
protocol StatusBarSource: AnyObject {
    /// Tasks that are working or waiting on the user, across every project, most urgent first.
    var statusBarTasks: [TaskActivity] { get }
    /// Each running agent's process, for sampling its memory and CPU.
    var statusBarAgentProcesses: [ProcessSampler.Root] { get }
    /// Shows a task in the main window.
    func showTask(_ id: SessionKey)
}

/// A task as the status bar lists it.
struct TaskActivity: Identifiable, Hashable {
    let id: SessionKey
    let title: String
    let agentName: String
    let projectName: String?
    /// `.working`, or what it's waiting for from the user.
    let status: TaskStatus

    var needsAttention: Bool {
        status.needsAttention
    }
}
