import Foundation
import NativeHostProtocol
import Observation

@Observable
final class CoordinatorTaskEditor {
    let project: Project
    let record: HostCoordinator?
    let creationID = HostSessionID()
    var selected: Set<SessionKey>
    var agentID: AgentDefinition.ID?
    var isSaving = false
    var error: String?
    private weak var app: AppModel?

    init(project: Project, record: HostCoordinator?, app: AppModel) {
        self.project = project
        self.record = record
        self.app = app
        selected = Set(
            (record?.assignments ?? []).map {
                SessionKey(agent: AgentDefinition.ID(rawValue: $0.agentID), id: $0.agentSessionID)
            })
        agentID = app.agents.first(where: { $0.isAvailable && !$0.needsSignIn })?.agent.id
    }

    var choices: [SessionSummary] { app?.coordinatorChoices(in: project.id, editing: record) ?? [] }
    var unavailableSelected: Set<SessionKey> { selected.subtracting(choices.map(\.id)) }
    var agents: [AgentRuntime] { app?.agents.filter { $0.isAvailable && !$0.needsSignIn } ?? [] }
    func title(for task: SessionSummary) -> String { app?.title(for: task) ?? "Untitled task" }

    func save() async {
        guard !isSaving, let app else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do { try await app.saveCoordinator(self) } catch { self.error = error.localizedDescription }
    }

    func cancel() { if !isSaving { app?.coordinatorEditor = nil } }
}
