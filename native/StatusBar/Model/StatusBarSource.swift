import AppAppearance
import Foundation

/// What the status bar's own items need from the app, so they depend on this rather than on the
/// app model's internals. `AppModel` conforms in `AppModel+StatusBarSource.swift`.
protocol StatusBarSource: AnyObject {
    /// Tasks that are working or waiting on the user, across every project; those waiting first,
    /// in sidebar order, so the first is the one ⌘Y and the bar's "needs you" go to.
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
    /// When its current turn started (the user's last prompt), for how long it's been working.
    let since: Date?
    var workingAnimation: WorkingAnimation? = nil

    var needsAttention: Bool {
        status.needsAttention
    }
}
