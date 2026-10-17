import Foundation

/// What workflow runs need from the app. Tasks are sessions, named by `SessionContext.clientID`;
/// the app reports their turns ending through `WorkflowRunner.turnEnded(task:outcome:)`.
@MainActor
protocol WorkflowHost: AnyObject {
    /// Agents that can run a step right now.
    var workflowAgents: [WorkflowAgent] { get }
    /// The agent steps run on when the workflow doesn't say.
    var defaultWorkflowAgent: WorkflowAgent.ID? { get }

    /// Creates an idle session on `agent` in `cwd` for a step: not in the sidebar, not under any
    /// other session, but reachable by its id. Returns its client id.
    func createStepTask(agent: WorkflowAgent.ID, title: String, cwd: URL) async throws -> UUID
    /// Sends `text` as the task's next prompt; returns once the turn is under way.
    func sendToStepTask(_ task: UUID, text: String) async throws
    /// Cancels the task's running turn.
    func cancelStepTask(_ task: UUID) async
    /// The task's state now, or nil if its session is gone. Built from observable state, since the
    /// run view reads it.
    func stepTaskReport(_ task: UUID) -> WorkflowTaskReport?
    /// Opens a pull request from the branch checked out in the draft's folder: the hook into the
    /// GitHub feature.
    func openPullRequest(_ draft: WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult
}
