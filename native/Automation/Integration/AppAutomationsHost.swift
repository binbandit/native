import Foundation
import NativeAutomation

/// The app as Automations sees it: runs start as workflow runs in the center's runner, worktrees
/// and GitHub come from the features the app wires in. The durable host gets its own implementation
/// when Automations moves there.
final class AppAutomationsHost: AutomationHost {
    private weak var center: AutomationCenter?
    private let repositoryLookup: (URL) async -> String?
    private let makeWorktree: (_ project: URL, _ title: String) async throws -> URL
    private let pullRequests: () async -> [PullRequestSnapshot]?

    init(
        center: AutomationCenter,
        repository: @escaping (URL) async -> String?,
        worktree: @escaping (_ project: URL, _ title: String) async throws -> URL,
        pullRequests: @escaping () async -> [PullRequestSnapshot]?
    ) {
        self.center = center
        repositoryLookup = repository
        makeWorktree = worktree
        self.pullRequests = pullRequests
    }

    var automationAgents: [WorkflowAgent] {
        center?.host?.workflowAgents ?? []
    }

    var workflowLibrary: WorkflowLibrary {
        center?.library ?? WorkflowLibrary()
    }

    func repository(of project: URL) async -> String? {
        await repositoryLookup(project)
    }

    func prepareWorkspace(for automation: Automation, title: String) async throws -> URL {
        switch automation.placement {
        case .mainCheckout: automation.project
        case .worktree: try await makeWorktree(automation.project, title)
        }
    }

    func startWorkflow(_ definition: WorkflowDefinition, input: String, cwd: URL, overrides: [String: WorkflowAgent.ID]) -> WorkflowRun.ID {
        guard let center else { return WorkflowRun.ID() }
        return center.workflows.start(definition, input: input, cwd: cwd, overrides: overrides)
    }

    func cancelWorkflowRun(_ id: WorkflowRun.ID) {
        center?.workflows.send(.cancel, to: id)
    }

    func workflowRun(_ id: WorkflowRun.ID) -> WorkflowRun? {
        center?.workflows.run(id)
    }

    func pullRequestSnapshots() async -> [PullRequestSnapshot]? {
        await pullRequests()
    }
}
