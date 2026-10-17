import ACP
import Foundation
import NativeHostProtocol

/// A connected client: the app, later the companion, or a test.
@HostActor
final class ClientLink {
    typealias ID = UUID

    let id: ID
    let peer: JSONRPCPeer
    var info: PeerInfo?
    var attached: Set<HostSessionID> = []

    init(id: ID, peer: JSONRPCPeer) {
        self.id = id
        self.peer = peer
    }

    /// Sends a notification. Writes queue on the channel, so this never waits on the client.
    func notify(_ method: String, _ params: some Encodable & Sendable) {
        try? peer.notify(method, params)
    }
}

// The client side of the protocol: every request a client can make, answered on the host actor.
extension HostCore {
    /// Takes a new connection and serves it until it closes.
    public func accept(_ stream: any ByteStream) {
        let id = ClientLink.ID()
        let peer = JSONRPCPeer(channel: stream, label: "client") { [weak self] event in
            await self?.receive(event, fromClient: id)
        }
        let client = ClientLink(id: id, peer: peer)
        clients[id] = client
        peer.start()
    }

    private func receive(_ event: JSONRPCPeer.Event, fromClient id: ClientLink.ID) {
        guard let client = clients[id] else { return }
        switch event {
        case .request(let message):
            // Each request runs on its own, so a slow one (starting an agent) doesn't hold up the rest.
            Task { await serve(message, from: client) }
        case .notification:
            break
        case .closed:
            for sessionID in client.attached {
                sessions[sessionID]?.subscribers.remove(id)
            }
            clients[id] = nil
        }
    }

    private func serve(_ message: JSONRPCPeer.Message, from client: ClientLink) async {
        guard let requestID = message.id else { return }
        do {
            try await answer(message, from: client) { result in
                try client.peer.respond(to: requestID, with: result)
            }
        } catch let error as RPCError {
            try? client.peer.respond(to: requestID, error: error)
        } catch let error as HostError {
            try? client.peer.respond(to: requestID, error: error.rpcError)
        } catch let error as DecodingError {
            try? client.peer.respond(to: requestID, error: .invalidParams(error))
        } catch {
            try? client.peer.respond(to: requestID, error: RPCError(code: -32000, message: error.localizedDescription))
        }
    }

    /// Handles one request. `reply` must be called, once, in the same actor turn as the state the
    /// result describes, so nothing slips in between (see `attach`).
    private func answer(_ message: JSONRPCPeer.Message, from client: ClientLink, reply: (any Encodable & Sendable) throws -> Void) async throws {
        typealias Method = HostProtocol.Method
        switch message.method {
        case Method.initialize:
            let params = try message.params(as: InitializeParams.self)
            client.info = params.clientInfo
            try reply(info)
        case Method.syncAgents:
            try syncAgents(try message.params(as: SyncAgentsParams.self).agents)
            try reply(EmptyMessage())
        case Method.listSessions:
            try reply(sessions.values.map(\.summary).sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) })
        case Method.newSession:
            try reply(try await newSession(try message.params(as: NewSessionParams.self)))
        case Method.openSession:
            try reply(try await openSession(try message.params(as: OpenSessionParams.self)))
        case Method.attach:
            try attach(try message.params(as: AttachParams.self), client: client, reply: reply)
        case Method.detach:
            let params = try message.params(as: SessionParams.self)
            client.attached.remove(params.sessionID)
            sessions[params.sessionID]?.subscribers.remove(client.id)
            try reply(EmptyMessage())
        case Method.prompt:
            try reply(PromptResult(delivery: try await prompt(try message.params(as: PromptParams.self))))
        case Method.cancel:
            await cancel(try session(try message.params(as: SessionParams.self).sessionID))
            try reply(EmptyMessage())
        case Method.respondPermission:
            try respondPermission(try message.params(as: RespondPermissionParams.self))
            try reply(EmptyMessage())
        case Method.setConfigOption:
            try await setConfigOption(try message.params(as: SetConfigOptionParams.self))
            try reply(EmptyMessage())
        case Method.updateQueued:
            try updateQueued(try message.params(as: QueueItemParams.self))
            try reply(EmptyMessage())
        case Method.removeQueued:
            try removeQueued(try message.params(as: QueueItemParams.self))
            try reply(EmptyMessage())
        case Method.sendQueuedNow:
            try await sendQueuedNow(try message.params(as: QueueItemParams.self))
            try reply(EmptyMessage())
        case Method.closeSession:
            try await closeSession(try message.params(as: SessionParams.self).sessionID)
            try reply(EmptyMessage())
        case Method.listActivity:
            let params = try message.params(as: ListActivityParams.self)
            try reply(try store.activity(after: params.after, limit: min(params.limit, 1_000)))
        case Method.shutdown:
            try reply(EmptyMessage())
            await shutdown(stopAgents: try message.params(as: ShutdownParams.self).stopAgents)
        default:
            throw RPCError.methodNotFound(message.method)
        }
    }

    /// Replays what the client hasn't seen as notifications, then answers, all in one actor turn:
    /// the client applies the replay, then live events, with nothing missed or doubled. A session
    /// the agent doesn't have loaded (after a restart) starts loading; its replay streams in live.
    private func attach(_ params: AttachParams, client: ClientLink, reply: (any Encodable & Sendable) throws -> Void) throws {
        let session = try session(params.sessionID)
        let afterSeq = params.epoch == epoch ? params.afterSeq : nil
        for event in session.events(after: afterSeq) {
            client.notify(HostProtocol.Method.sessionEvent, SessionEventNotification(sessionID: session.id, event: event))
        }
        session.subscribers.insert(client.id)
        client.attached.insert(session.id)
        try reply(AttachResult(summary: session.summary))
        if session.needsLoad, session.turn == nil, session.record.origin != .announced {
            Task { try? await load(session) }
        }
    }
}
