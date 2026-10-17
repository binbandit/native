import ACP
import Foundation
import NativeHostProtocol

// What agents send: session updates, permission requests, and their processes exiting (see
// `HostCore+Recovery.swift` for what happens then).
extension HostCore {
    func receive(_ event: JSONRPCPeer.Event, from agentID: String, generation: Int) {
        guard let link = agents[agentID], link.generation == generation else { return }
        switch event {
        case .notification(let message) where message.method == "session/update":
            guard let notification = try? message.params(as: RawSessionNotification.self) else { return }
            if let id = link.routes[notification.sessionId], let session = sessions[id] {
                apply(notification.update, to: session, on: link)
            } else {
                link.buffer(notification.update, for: notification.sessionId)
            }
        case .notification:
            break
        case .request(let message):
            receiveRequest(message, from: link)
        case .closed:
            agentExited(agentID, generation: generation)
        }
    }

    func receiveRequest(_ message: JSONRPCPeer.Message, from link: AgentLink) {
        guard let id = message.id, let peer = link.peer else { return }
        guard message.method == "session/request_permission" else {
            // Native advertises no optional client capabilities, so anything else (fs, terminals)
            // is unexpected.
            try? peer.respond(to: id, error: .methodNotFound(message.method))
            return
        }
        guard let request = try? message.params(as: RawPermissionRequest.self), let raw = message.rawParams,
            let sessionID = link.routes[request.sessionId], let session = sessions[sessionID]
        else {
            try? peer.respond(to: id, with: RequestPermissionResponse.cancelled)
            return
        }
        let toolCallID = request.toolCall.toolCallId
        session.pendingPermissions[toolCallID] = id
        append(.permissionRequested(toolCallID: toolCallID, request: raw), to: session)
        try? store.addApproval(sessionID: session.id, toolCallID: toolCallID, title: request.toolCall.title)
        journal(.approvalNeeded, session: session, detail: request.toolCall.title)
        publish(session)
    }

    /// An agent update for a session. A subagent the agent announces becomes a session of its own,
    /// so its traffic has somewhere to go.
    func apply(_ update: JSONValue, to session: HostSession, on link: AgentLink) {
        if update["sessionUpdate"]?.stringValue == "subagent_update"
            || update["sessionUpdate"]?.stringValue == "subagent_spawned",
            let child = update["sessionId"]?.stringValue.map(SessionID.init), link.routes[child] == nil
        {
            adoptSubagent(child, of: session, on: link)
        }
        let hadTitle = session.record.title
        append(.update(update), to: session)
        if session.record.title != hadTitle {
            try? store.updateSession(session.record)
            publish(session)
        }
    }

    func adoptSubagent(_ agentSessionID: SessionID, of parent: HostSession, on link: AgentLink) {
        // Subagents live as long as their parent's agent process; the parent's replay brings them back.
        let record = StoredSession(
            id: HostSessionID(), agentID: parent.record.agentID, agentSessionID: agentSessionID, cwd: parent.record.cwd,
            parentID: parent.id, origin: .announced
        )
        let child = HostSession(record: record, agentName: parent.agentName, phase: .idle, needsLoad: false)
        sessions[record.id] = child
        append(.reset(loading: false), to: child)
        route(child, on: link)
        publish(child)
    }
}
