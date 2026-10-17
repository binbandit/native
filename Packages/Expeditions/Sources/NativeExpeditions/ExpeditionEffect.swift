import Foundation
import NativeAutomation

/// Work an expedition asks its host to do. The expedition decides; `ExpeditionRunner` carries these
/// out and reports back with `ExpeditionEvent`s.
public nonisolated enum ExpeditionEffect: Codable, Hashable, Sendable {
    /// Make the workspace the crew shares; answer with `baseReady` or `baseFailed`.
    case prepareBase(project: URL, title: String, worktree: Bool)
    /// Create a session for `slot`; answer with `taskCreated` or `taskFailed`.
    case createTask(CrewSlot, agent: WorkflowAgent, title: String, cwd: URL)
    /// Send `text` as the session's next prompt; answer with `taskFailed` if it can't go out.
    case prompt(CrewSlot, task: UUID, text: String)
    /// Hand the user's `text` to a session that's working: steered into the running turn where the
    /// agent supports it, queued as its next prompt otherwise.
    case message(CrewSlot, task: UUID, text: String)
    case cancelTask(UUID)
    /// Answer with `pullRequestOpened` or `pullRequestFailed`.
    case openPullRequest(WorkflowPullRequestDraft)
}
