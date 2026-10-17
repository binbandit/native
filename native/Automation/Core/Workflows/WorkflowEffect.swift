import Foundation

/// Work a run asks its host to do. The run decides; `WorkflowRunner` carries these out and reports
/// back with `WorkflowEvent`s.
nonisolated enum WorkflowEffect: Hashable, Sendable {
    /// Create a task session for `step` on `agent`; answer with `taskCreated` or `taskFailed`.
    case createTask(step: String, agent: WorkflowAgent, title: String)
    /// Send `text` as the next prompt of `task`; answer with `taskFailed` if it can't go out.
    case prompt(step: String, task: UUID, text: String)
    case cancelTask(UUID)
    /// Answer with `pullRequestOpened` or `pullRequestFailed`.
    case openPullRequest(step: String, WorkflowPullRequestDraft)
}
