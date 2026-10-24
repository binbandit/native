import Foundation
import NativeHostProtocol
import NativeOrchestration

extension HostTasks {
    func coordinatorScope(of clientID: UUID) -> CoordinatorScope? {
        guard let session = core.sessions[HostSessionID(clientID)], let identity = HostTaskIdentity(session),
            let record = core.coordinators.first(where: { $0.task == identity || $0.hostSessionID == session.id })
        else { return nil }
        let tasks = record.assignments.compactMap { target -> OrchestrationTask? in
            guard let assigned = core.coordinatorSession(target) else { return nil }
            return OrchestrationTask(
                id: "task-\(assigned.id)", session: target.reference, agentName: assigned.agentName,
                title: assigned.record.title ?? "Untitled task", parent: identity.reference,
                parentAgentName: session.agentName, cwd: assigned.record.cwd)
        }
        return CoordinatorScope(title: session.record.title ?? "Coordinator", tasks: tasks)
    }

    func openCoordinatedTask(_ ref: TaskSessionRef) async throws {
        // Reads use the retained mirror. Loading an unsaved agent conversation can replace its
        // identity; delivery loads it only after capturing the durable sender and recipient.
        guard session(holding: ref) != nil else { throw HostTaskError.closed }
    }

    func recentTranscript(of ref: TaskSessionRef) -> String? {
        session(holding: ref).map { CoordinatorScope.summary(of: $0.mirror.state) }
    }
}
