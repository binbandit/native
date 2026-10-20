import ACP
import Foundation
import NativeHostProtocol

// What agents send: session updates, the requests they make of the user (permissions and
// questions), and their processes exiting (see `HostCore+Recovery.swift` for what happens then).
extension HostCore {
    func receive(_ event: JSONRPCPeer.Event, from agentID: String, generation: Int) {
        guard let link = agents[agentID], link.generation == generation else { return }
        switch event {
        case .notification(let message) where message.method == "session/update":
            // The hot path while an agent streams (`AgentUpdate`).
            guard let (sessionID, update) = AgentUpdate.parse(message.line) else { return }
            if let id = link.routes[sessionID], let session = sessions[id] {
                apply(update, to: session, on: link)
            } else {
                link.buffer(update, for: sessionID)
            }
        case .notification(let message) where Self.signInNotifications.contains(message.method):
            receiveSignInNotification(message, from: link)
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
        switch message.method {
        case "session/request_permission":
            requestPermission(message, id: id, from: link)
        case "elicitation/create" where Self.isSignInLink(message):
            receiveSignInLink(message, id: id, from: link)
        case "elicitation/create":
            askQuestion(message, id: id, from: link)
        default:
            // Native advertises no other client capabilities (fs, terminals), so nothing else is
            // expected.
            try? peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }

    private func requestPermission(_ message: JSONRPCPeer.Message, id: RequestID, from link: AgentLink) {
        guard let request = try? message.params(as: RawPermissionRequest.self), let raw = message.rawParams,
            let sessionID = link.routes[request.sessionId], let session = sessions[sessionID]
        else {
            try? link.peer?.respond(to: id, with: RequestPermissionResponse.cancelled)
            return
        }
        let toolCallID = request.toolCall.toolCallId
        session.pendingPermissions[toolCallID] = id
        append(.permissionRequested(toolCallID: toolCallID, request: raw), to: session)
        try? store.addApproval(sessionID: session.id, toolCallID: toolCallID, title: request.toolCall.title)
        journal(.approvalNeeded, session: session, detail: request.toolCall.title)
        publish(session)
    }

    /// A question for the user (`elicitation/create`). Only forms can be answered; anything else is
    /// cancelled so the agent isn't left waiting.
    private func askQuestion(_ message: JSONRPCPeer.Message, id: RequestID, from link: AgentLink) {
        guard let request = try? message.params(as: CreateElicitationRequest.self), let raw = message.rawParams,
            request.mode == .form, request.requestedSchema != nil,
            let sessionID = link.routes[request.sessionId], let session = sessions[sessionID]
        else {
            try? link.peer?.respond(to: id, with: CreateElicitationResponse.cancel)
            return
        }
        let questionID = UUID().uuidString
        session.pendingQuestions.append((questionID, id))
        append(.questionAsked(questionID: questionID, request: raw), to: session)
        journal(.questionAsked, session: session, detail: request.message)
        publish(session)
    }

    func respondPermission(_ params: RespondPermissionParams) throws {
        let session = try session(params.sessionID)
        guard let requestID = session.pendingPermissions.removeValue(forKey: params.toolCallID) else {
            throw HostError.permissionNotPending
        }
        let response = params.optionID.map { RequestPermissionResponse.selected(optionId: $0) } ?? .cancelled
        try? agents[session.record.agentID]?.peer?.respond(to: requestID, with: response)
        append(.permissionResolved(toolCallID: params.toolCallID, optionID: params.optionID), to: session)
        try? store.removeApproval(sessionID: session.id, toolCallID: params.toolCallID)
        publish(session)
    }

    /// Answers a question with the client's response, verbatim. The first client to answer wins.
    func respondQuestion(_ params: RespondQuestionParams) throws {
        let session = try session(params.sessionID)
        guard let index = session.pendingQuestions.firstIndex(where: { $0.id == params.questionID }) else {
            throw HostError.questionNotPending
        }
        let question = session.pendingQuestions.remove(at: index)
        try? agents[session.record.agentID]?.peer?.respond(to: question.request, with: params.response)
        append(.questionResolved(questionID: params.questionID), to: session)
        publish(session)
    }

    /// Drops permission requests that can't be answered any more (the turn ended, or the agent died).
    func withdrawPermissions(of session: HostSession) {
        for toolCallID in session.pendingPermissions.keys.sorted() {
            append(.permissionResolved(toolCallID: toolCallID, optionID: nil), to: session)
        }
        session.pendingPermissions = [:]
        try? store.removeApprovals(sessionID: session.id)
    }

    /// Withdraws open questions, answering them as cancelled where the agent can still hear it.
    func withdrawQuestions(of session: HostSession) {
        let peer = agents[session.record.agentID]?.peer
        for question in session.pendingQuestions {
            try? peer?.respond(to: question.request, with: CreateElicitationResponse.cancel)
            append(.questionResolved(questionID: question.id), to: session)
        }
        session.pendingQuestions = []
    }

    /// An agent update for a session. A subagent the agent announces becomes a session of its own,
    /// so its traffic has somewhere to go. While a hidden command runs, its reply is collected
    /// instead of logged, and late copies of it are dropped.
    func apply(_ update: AgentUpdate, to session: HostSession, on link: AgentLink) {
        if update.kind == "agent_message_chunk", session.hiddenCommand != nil || session.hiddenCommandEcho != nil,
            let decoded = update.decoded
        {
            if session.hiddenCommand?.capture(decoded) == true {
                return
            }
            if session.turn == nil, session.hiddenCommandEcho?.isEcho(decoded) == true {
                return
            }
        }
        if update.kind == "subagent_update" || update.kind == "subagent_spawned", let child = update.sessionID,
            link.routes[child] == nil
        {
            adoptSubagent(child, of: session, on: link)
        }
        let hadTitle = session.record.title
        append(update, to: session)
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
        // Published before the parent's update that announces it, so clients can attach to it first.
        publish(child)
    }
}
