import ACP
import Foundation
import Observation

/// The session models open in this run, subagents included, and the routing of each agent's
/// events to them.
@Observable
final class SessionStore {
    private var sessions: [SessionKey: SessionModel] = [:]
    /// Updates for sessions whose model doesn't exist yet. An agent can send these before it answers
    /// `session/new`.
    private var buffered: [SessionKey: [SessionUpdate]] = [:]
    @ObservationIgnored private let services: SessionServices

    init(services: SessionServices) {
        self.services = services
    }

    func session(_ key: SessionKey) -> SessionModel? {
        sessions[key]
    }

    /// Looks a session up by the agent's id for it, whichever agent that is. Ids could collide
    /// across agents, so prefer `session(_:)` when the agent is known.
    func session(id: SessionID) -> SessionModel? {
        sessions.first { $0.key.id == id }?.value
    }

    /// Looks a session up by Native's own id for it, for plugins that key resources by that.
    func session(clientID: UUID) -> SessionModel? {
        sessions.values.first { $0.clientID == clientID }
    }

    /// The agent's sessions open now, subagents included.
    func open(of agent: AgentDefinition.ID) -> [SessionModel] {
        sessions.filter { $0.key.agent == agent }.map(\.value)
    }

    /// Adds a session and delivers whatever arrived for it before it existed.
    func register(_ session: SessionModel) {
        sessions[session.key] = session
        for update in buffered.removeValue(forKey: session.key) ?? [] {
            deliver(update, to: session)
        }
    }

    /// Drops a session and its subagents, for when Native closes it.
    func remove(_ session: SessionModel) {
        for child in session.children.values {
            remove(child)
        }
        sessions[session.key] = nil
    }

    /// Drops an agent's sessions, for when its process is replaced or goes away for good.
    func removeAll(of agent: AgentDefinition.ID) {
        sessions = sessions.filter { $0.key.agent != agent }
        buffered = buffered.filter { $0.key.agent != agent }
    }

    /// Routes one of `agent`'s events. `connection` answers permission requests for sessions that
    /// aren't open.
    func handle(_ event: AgentEvent, from agent: AgentDefinition.ID, connection: ACPConnection?) {
        switch event {
        case .sessionUpdate(let notification):
            let key = SessionKey(agent: agent, id: notification.sessionId)
            if let session = sessions[key] {
                deliver(notification.update, to: session)
            } else {
                buffered[key, default: []].append(notification.update)
            }
        case .permissionRequest(let id, let request):
            if let session = sessions[SessionKey(agent: agent, id: request.sessionId)] {
                session.requestPermission(request, id: id)
                services.post(.permissionRequested(session.context, toolCall: request.toolCall.title ?? "Tool call"))
            } else if let connection {
                Task { try? await connection.respond(to: id, with: RequestPermissionResponse.cancelled) }
            }
        case .elicitationRequest(let id, let request):
            if let session = sessions[SessionKey(agent: agent, id: request.sessionId)] {
                session.requestQuestion(request, id: id)
                services.post(.questionAsked(session.context, message: request.message))
            } else if let connection {
                Task { try? await connection.respond(to: id, with: CreateElicitationResponse.cancel) }
            }
        case .disconnected:
            disconnect(agent, isRestarting: false)
        }
    }

    /// Marks an agent's sessions as cut off from it, returning the user's sessions whose turn it
    /// interrupted.
    @discardableResult
    func disconnect(_ agent: AgentDefinition.ID, isRestarting: Bool) -> [SessionKey] {
        var interrupted: [SessionKey] = []
        for (key, session) in sessions where key.agent == agent {
            if session.phase == .prompting, session.origin == .user {
                interrupted.append(key)
            }
            session.markDisconnected(isRestarting: isRestarting)
        }
        return interrupted
    }

    private func deliver(_ update: SessionUpdate, to session: SessionModel) {
        // Agents announce a subagent on its parent before sending anything under the subagent's id,
        // so its model has to exist from here on; registering it also picks up anything buffered.
        if case .subagent(let subagent) = update, session.child(subagent.sessionId) == nil {
            register(session.addSubagent(subagent.sessionId))
        }
        session.apply(update)
    }
}
