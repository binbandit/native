import ACP
import Foundation
import NativeAutomation

/// The app as workflows see it, built on `AppModel`'s public API: step tasks are detached task
/// sessions (`startTaskSession`), prompted through `submit` like any session.
final class AppAutomationHost: WorkflowHost {
    private weak var model: AppModel?
    /// Opens a pull request through the GitHub feature. The app wires it; until then pull request
    /// steps fail with a way out (skip, or open it by hand).
    var openPullRequestHandler: ((WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult)?
    /// Runs a script step in the script runtime (docs/script-runtime.md) once it exists.
    var runScriptHandler: ((_ source: String, _ input: String, _ cwd: URL) async throws -> String)?

    private let records: StepTaskRecords
    /// Steps whose sessions were reopened this launch: the run's task id to the session's new
    /// client id.
    private var reopened: [UUID: UUID] = [:]

    init(model: AppModel, records: StepTaskRecords = .standard) {
        self.model = model
        self.records = records
    }

    /// A step's session, for the run view to show its transcript.
    func session(for task: UUID) -> SessionModel? {
        model?.session(clientID: reopened[task] ?? task)
    }

    /// The task a session's events belong to: the run's original id for a reopened step session.
    func task(forClient clientID: UUID) -> UUID {
        reopened.first { $0.value == clientID }?.key ?? clientID
    }

    /// The step's session, reopening it from the agent when it didn't survive a restart.
    private func liveSession(for task: UUID) async throws -> SessionModel {
        if let session = session(for: task) {
            return session
        }
        guard let model, let record = records[task] else { throw AutomationHostError.taskClosed }
        let session = try await model.reopenTaskSession(agent: AgentDefinition.ID(rawValue: record.agent), id: record.session, cwd: record.cwd)
        reopened[task] = session.clientID
        return session
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
        records.remember(StepTaskRecords.Record(agent: agent, session: session.id, cwd: session.cwd), for: session.clientID)
        return session.clientID
    }

    func sendToStepTask(_ task: UUID, text: String) async throws {
        try await liveSession(for: task).submit(text, .queue)
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

    func runScript(_ source: String, input: String, cwd: URL) async throws -> String {
        guard let runScriptHandler else { throw AutomationHostError.scriptsUnavailable }
        return try await runScriptHandler(source, input, cwd)
    }
}
