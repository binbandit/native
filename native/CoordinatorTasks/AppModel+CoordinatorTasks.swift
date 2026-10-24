import ACP
import Experiments
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeOrchestration
import NativePolicy
import Undo

extension AppModel {
    /// Resolve the gate once for every entry point and sidebar presentation.
    var offersCoordinatorTasks: Bool { experiments.value(of: .coordinatorTasks) }

    func coordinator(for key: SessionKey) -> HostCoordinator? {
        coordinators.first { $0.task == key.coordinatorIdentity }
    }

    func coordinatorConversationBlock(for key: SessionKey) -> String? {
        if coordinator(for: key) != nil {
            return "Create a new coordinator and reassign its tasks to start a fresh conversation or use another agent."
        }
        if coordinators.contains(where: { $0.assignments.contains(key.coordinatorIdentity) }) {
            return
                "Remove this task from its coordinator with Edit Assigned Tasks before clearing its conversation or changing agents."
        }
        return nil
    }

    func requestCoordinator(editing key: SessionKey? = nil) {
        guard offersCoordinatorTasks, coordinatorEditor == nil, let project = currentProject else { return }
        coordinatorEditor = CoordinatorTaskEditor(project: project, record: key.flatMap(coordinator), app: self)
    }

    func coordinatorChoices(in project: Project.ID, editing: HostCoordinator?) -> [SessionSummary] {
        allSessions(in: project).filter { summary in
            !isArchived(summary.id) && !pendingDeletionKeys.contains(summary.id)
                && !earlierConversations.isSetAside(summary.id)
                && coordinator(for: summary.id) == nil && device(of: summary.id) == .thisMac
                && !coordinators.contains {
                    $0.task != editing?.task && $0.assignments.contains(summary.id.coordinatorIdentity)
                }
        }
    }

    func saveCoordinator(_ editor: CoordinatorTaskEditor) async throws {
        guard offersCoordinatorTasks, projects.project(editor.project.id) != nil,
            editor.project.host == .local,
            plugins.isEnabled(OrchestrationPlugin.id), HostTasksSetting.isEnabled,
            PolicyCenter.shared.policy.mcp.allows(name: OrchestrationPlugin.serverName),
            let client = runtimes.host
        else {
            throw CoordinatorTaskFailure(
                "Coordinators need a local project and Native's host orchestration tools. Enable them and try again.")
        }
        let candidates = coordinatorChoices(in: editor.project.id, editing: editor.record)
        let selected = candidates.filter { editor.selected.contains($0.id) }
        guard selected.count == editor.selected.count else {
            throw CoordinatorTaskFailure(
                "Some selected tasks are no longer available. Reopen the picker and choose active tasks.")
        }
        // Open only tasks the trusted client lists in this project, including its worktrees.
        for summary in selected {
            if let existing = sessions.session(summary.id), existing.host?.client === client { continue }
            guard let runtime = await ensureRunning(summary.agent.id), runtime.host === client else {
                throw CoordinatorTaskFailure("A selected task's agent is unavailable. Start it and try again.")
            }
            _ = try await launcher.load(
                summary.id, cwd: URL(filePath: summary.info.cwd), on: runtime)
        }
        let assignments = selected.map { $0.id.coordinatorIdentity }
        if var record = editor.record {
            record.assignments = assignments
            try await client.setCoordinator(record)
            coordinators.removeAll { $0.task == record.task }
            coordinators.append(record)
            if let previous = editor.record {
                offerUndo("Assigned tasks updated", name: "Edit Assigned Tasks", undoManager: undoHistory.manager) {
                    model in
                    Task {
                        do {
                            try await client.setCoordinator(previous)
                            model.coordinators.removeAll { $0.task == previous.task }
                            model.coordinators.append(previous)
                        } catch {
                            model.actionFailure = ActionFailure(
                                "Couldn't Restore Assignments", error.localizedDescription)
                        }
                    }
                }
            }
        } else {
            guard let agent = editor.agentID, let runtime = await ensureRunning(agent), runtime.host === client else {
                throw CoordinatorTaskFailure("Choose an available agent running on this Mac.")
            }
            let session = try await launcher.startOnHost(
                client, on: runtime, cwd: editor.project.url, origin: .user, parent: nil,
                coordinatorAssignments: assignments, coordinatorID: editor.creationID)
            catalog.add(
                SessionInfo(sessionId: session.id, cwd: session.cwd.folderPath, updatedAt: .now),
                for: session.agent.id, in: editor.project.id)
            titles.rename(session.titleKey, to: "Coordinator")
            coordinators.removeAll { $0.hostSessionID == editor.creationID }
            coordinators.append(
                HostCoordinator(
                    task: session.key.coordinatorIdentity,
                    projectPath: editor.project.path, assignments: assignments, hostSessionID: editor.creationID))
            selection = session.key
            session.wantsComposerFocus = true
        }
        coordinatorEditor = nil
    }

    /// Deleting the owner releases its tasks without cancelling any of them.
    func releaseCoordinatorAssignments(beforeDeleting key: SessionKey) async throws {
        guard var record = coordinator(for: key), !record.assignments.isEmpty else { return }
        guard let client = runtimes.host else {
            throw CoordinatorTaskFailure(
                "Reconnect the local host to release this coordinator's assigned tasks, then delete it again.")
        }
        record.assignments = []
        try await client.setCoordinator(record)
        coordinators.removeAll { $0.task == record.task }
        coordinators.append(record)
    }

    func followCoordinators(on client: NativeHostClient) async {
        if followedCoordinatorClients.insert(ObjectIdentifier(client)).inserted {
            await client.addCoordinatorHandler { [weak self] records in
                await MainActor.run { self?.coordinators = records }
            }
        }
        // Older hosts have no coordinator endpoint. Creation still reports that failure explicitly.
        if let records = try? await client.coordinators() { coordinators = records }
    }

    /// Shared by the sidebar and keyboard navigation, including pinned tasks.
    func groupCoordinatorTasks(_ lists: [[SessionSummary]]) -> [[SessionSummary]] {
        guard offersCoordinatorTasks else { return lists }
        let lookup = Dictionary(lists.flatMap { $0 }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let assignments = Dictionary(
            uniqueKeysWithValues: coordinators.map { record in
                (
                    SessionKey(
                        agent: AgentDefinition.ID(rawValue: record.task.agentID), id: record.task.agentSessionID),
                    record.assignments.map {
                        SessionKey(agent: AgentDefinition.ID(rawValue: $0.agentID), id: $0.agentSessionID)
                    }
                )
            })
        return CoordinatorOrdering.grouped(lists.map { $0.map(\.id) }, assignments: assignments)
            .map { $0.compactMap { lookup[$0] } }
    }

    func isCoordinatorChild(_ key: SessionKey, among visible: [SessionSummary]) -> Bool {
        guard offersCoordinatorTasks else { return false }
        let keys = Set(visible.map { $0.id.coordinatorIdentity })
        return coordinators.contains { keys.contains($0.task) && $0.assignments.contains(key.coordinatorIdentity) }
    }
}

extension SessionKey {
    var coordinatorIdentity: HostTaskIdentity { HostTaskIdentity(agentID: agent.rawValue, agentSessionID: id) }
}

struct CoordinatorTaskFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
