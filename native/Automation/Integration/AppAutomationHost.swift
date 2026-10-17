import ACP
import Foundation

/// The app as workflows see it, built on `AppModel`'s public API: step tasks are detached task
/// sessions (`startTaskSession`), prompted through `submit` like any session.
final class AppAutomationHost: WorkflowHost {
    private weak var model: AppModel?
    /// Opens a pull request through the GitHub feature. The app wires it; until then pull request
    /// steps fail with a way out (skip, or open it by hand).
    var openPullRequestHandler: ((WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult)?

    init(model: AppModel) {
        self.model = model
    }

    /// A step's session, for the run view to show its transcript.
    func session(for task: UUID) -> SessionModel? {
        model?.session(clientID: task)
    }

    // MARK: - WorkflowHost

    var workflowAgents: [WorkflowAgent] {
        (model?.agents ?? []).filter(\.isReady).map { runtime in
            WorkflowAgent(id: runtime.agent.id.rawValue, name: runtime.agent.displayName, symbol: runtime.agent.symbolName)
        }
    }

    var defaultWorkflowAgent: WorkflowAgent.ID? {
        model?.defaultAgent?.id.rawValue
    }

    func createStepTask(agent: WorkflowAgent.ID, title: String, cwd: URL) async throws -> UUID {
        guard let model else { throw AutomationHostError.appUnavailable }
        let session = try await model.startTaskSession(agent: AgentDefinition.ID(rawValue: agent), cwd: cwd)
        model.rename(session.key, to: title)
        return session.clientID
    }

    func sendToStepTask(_ task: UUID, text: String) async throws {
        guard let session = session(for: task) else { throw AutomationHostError.taskClosed }
        try await session.submit(text, .queue)
    }

    func cancelStepTask(_ task: UUID) async {
        await session(for: task)?.cancel()
    }

    func stepTaskReport(_ task: UUID) -> WorkflowTaskReport? {
        guard let session = session(for: task) else { return nil }
        return WorkflowTaskReport(reply: session.state.latestReply, cost: session.state.usage?.cost?.amount, needsApproval: session.needsApproval)
    }

    func openPullRequest(_ draft: WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult {
        guard let openPullRequestHandler else { throw AutomationHostError.pullRequestsUnavailable }
        return try await openPullRequestHandler(draft)
    }
}
