import Foundation

/// What Automations needs from wherever it runs: the app today, the durable host later.
@MainActor
public protocol AutomationHost: AnyObject {
    var automationAgents: [WorkflowAgent] { get }
    var workflowLibrary: WorkflowLibrary { get }
    /// The project's GitHub repository (`owner/name`), or nil if it has none.
    func repository(of project: URL) async -> String?
    /// The folder a run works in: a fresh worktree named after `title`, or the project itself.
    func prepareWorkspace(for automation: Automation, title: String) async throws -> URL
    /// Starts a workflow run; `overrides` pick agents by step id.
    func startWorkflow(_ definition: WorkflowDefinition, input: String, cwd: URL, overrides: [String: WorkflowAgent.ID]) -> WorkflowRun.ID
    func cancelWorkflowRun(_ id: WorkflowRun.ID)
    func workflowRun(_ id: WorkflowRun.ID) -> WorkflowRun?
    /// The user's open pull requests as GitHub reports them now; nil when GitHub isn't available.
    func pullRequestSnapshots() async -> [PullRequestSnapshot]?
}
