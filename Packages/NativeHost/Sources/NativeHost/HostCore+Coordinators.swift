import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration

extension HostCore {
    /// Only the trusted local client assigns tasks. Agents have no assignment tool.
    func setCoordinator(_ record: HostCoordinator, by client: ClientLink) throws -> EmptyMessage {
        guard client.grants.isLocal else { throw HostError.notAuthorized("assign coordinator tasks") }
        guard let existing = coordinators.first(where: { $0.task == record.task }),
            existing.projectPath == record.projectPath, existing.hostSessionID == record.hostSessionID
        else { throw CoordinatorFailure("That coordinator is no longer available. Reopen its task and try again.") }
        try validateAssignments(record.assignments, coordinator: record.task)
        try saveCoordinator(record)
        return EmptyMessage()
    }

    func newCoordinator(_ params: NewCoordinatorParams, by client: ClientLink) async throws -> HostSessionSummary {
        guard client.grants.isLocal else { throw HostError.notAuthorized("create coordinator tasks") }
        guard tasks.servesTools, params.task.parentID == nil, params.task.origin == .user else {
            throw CoordinatorFailure("Enable Native's host orchestration tools before creating a coordinator.")
        }
        if let id = params.task.sessionID, let existing = sessions[id] {
            guard let saved = coordinators.first(where: { $0.hostSessionID == id }) else {
                throw CoordinatorFailure("That task is not a coordinator. Start a new coordinator task.")
            }
            guard Set(saved.assignments) == Set(params.assignments), existing.record.agentID == params.task.agentID,
                existing.record.cwd == params.task.cwd
            else {
                throw CoordinatorFailure(
                    "This coordinator was already created. Open it and choose Edit Assigned Tasks to change its assignments."
                )
            }
            if params.task.attach { follow(existing, by: client) }
            return existing.summary
        }
        let id = params.task.sessionID ?? HostSessionID()
        if let starting = coordinatorStarts[id] { return try await starting.value }
        try validateAssignments(params.assignments, coordinator: nil)
        var params = params
        params.task.sessionID = id
        let starting = Task {
            try await newSession(params.task, follower: params.task.attach ? client : nil, coordinator: params)
        }
        coordinatorStarts[id] = starting
        defer { coordinatorStarts[id] = nil }
        return try await starting.value
    }

    func validateAssignments(_ assignments: [HostTaskIdentity], coordinator: HostTaskIdentity?) throws {
        guard Set(assignments).count == assignments.count else {
            throw CoordinatorFailure("A task can only be assigned once.")
        }
        for identity in assignments {
            guard identity != coordinator, !coordinators.contains(where: { $0.task == identity }),
                let target = coordinatorSession(identity), target.record.origin == .user,
                target.record.parentID == nil
            else { throw CoordinatorFailure("Choose active tasks, excluding coordinators and subagents.") }
            guard !coordinators.contains(where: { $0.task != coordinator && $0.assignments.contains(identity) }) else {
                throw CoordinatorFailure(
                    "A selected task already belongs to another coordinator. Remove that assignment first.")
            }
        }
    }

    func coordinatorSession(_ identity: HostTaskIdentity) -> HostSession? {
        sessions.values.first {
            $0.record.agentID == identity.agentID && $0.record.agentSessionID == identity.agentSessionID
        }
    }

    func saveCoordinator(_ record: HostCoordinator) throws {
        var updated = coordinators.filter { $0.task != record.task }
        updated.append(record)
        try persistCoordinators(updated)
    }

    func persistCoordinators(_ updated: [HostCoordinator]) throws {
        try store.setMeta(Self.coordinatorsKey, String(decoding: try JSONEncoder().encode(updated), as: UTF8.self))
        coordinators = updated
        for client in clients.values { client.notify(HostProtocol.Method.coordinatorsChanged, updated) }
    }

    /// Applied before publishing the task, independent of the user's ordinary new-task defaults.
    func coordinatorReadOnly(
        _ response: RawNewSessionResponse, on peer: JSONRPCPeer
    ) async throws -> JSONValue {
        guard let reported = response.configOptions,
            let choice = CoordinatorScope.readOnlyChoice(in: Self.configOptions(reported))
        else {
            throw CoordinatorFailure(
                "This agent does not advertise read-only access. Choose an agent with a read-only autonomy setting.")
        }
        let updated = try await peer.request(
            "session/set_config_option",
            RawSetConfigOptionRequest(sessionId: response.sessionId, configId: choice.option.id, value: choice.value),
            as: RawConfigOptionsResponse.self)
        guard let options = updated.configOptions,
            Self.configValues(Self.configOptions(options))[choice.option.id] == choice.value
        else {
            throw CoordinatorFailure(
                "The agent did not accept read-only access. No coordinator was created. Try another agent.")
        }
        return options
    }

    /// The agent session has never received a prompt and must not appear as an ordinary task.
    func discardCoordinatorCandidate(_ id: SessionID, on link: AgentLink, peer: JSONRPCPeer) async {
        let method: String
        if link.capabilities?.deleteSessions == true {
            method = "session/delete"
        } else if link.capabilities?.closeSessions == true {
            method = "session/close"
        } else {
            return
        }
        _ = try? await peer.request(method, RawSessionIDRequest(sessionId: id), as: JSONValue.self)
        link.buffered[id] = nil
    }

    static let coordinatorsKey = "coordinator_tasks_v1"
}

struct CoordinatorFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension HostTaskIdentity {
    @HostActor init?(_ session: HostSession) {
        guard let id = session.record.agentSessionID else { return nil }
        self.init(agentID: session.record.agentID, agentSessionID: id)
    }

    var reference: TaskSessionRef { TaskSessionRef(agent: agentID, id: agentSessionID.rawValue) }
}
