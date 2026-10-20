import ACP
import Foundation
import NativeHostProtocol

/// What a client may do beyond using sessions. Paired devices (docs/durability.md, "Transport and
/// security") are granted these when they pair; the owner has all of them.
public struct ClientGrants: Hashable, Sendable {
    /// Turn plugins on or off for everyone using this host.
    public var managePlugins: Bool
    /// Install updates and restart the host. On by default for devices paired by QR; revocable.
    public var manageHost: Bool
    /// The client runs on this machine as this user (the socket's peer checks), or reaches it over
    /// that user's SSH. Only such a client is the Mac app that reports Sparkle's status.
    public var isLocal: Bool

    public init(managePlugins: Bool, manageHost: Bool, isLocal: Bool) {
        self.managePlugins = managePlugins
        self.manageHost = manageHost
        self.isLocal = isLocal
    }

    public static let owner = ClientGrants(managePlugins: true, manageHost: true, isLocal: true)
}

/// A connected client: the app, later the companion, or a test.
@HostActor
final class ClientLink {
    typealias ID = UUID

    let id: ID
    let peer: JSONRPCPeer
    let grants: ClientGrants
    var info: PeerInfo?
    var attached: Set<HostSessionID> = []

    init(id: ID, peer: JSONRPCPeer, grants: ClientGrants) {
        self.id = id
        self.peer = peer
        self.grants = grants
    }

    /// Sends a notification. Writes queue on the channel, so this never waits on the client.
    func notify(_ method: String, _ params: some Encodable & Sendable) {
        try? peer.notify(method, params)
    }

    func notify(_ method: String, encodedParams params: Data) {
        try? peer.notify(method, encodedParams: params)
    }

    /// Sends a session's logged events, as `_native/session/event` notifications.
    func send(_ events: some Sequence<LoggedEvent>, of session: HostSessionID) {
        for event in events {
            notify(HostProtocol.Method.sessionEvent, encodedParams: Self.eventParams(event, of: session))
        }
    }

    /// A `SessionEventNotification`, around an event encoded already.
    static func eventParams(_ event: LoggedEvent, of session: HostSessionID) -> Data {
        var params = Data(#"{"sessionID":""#.utf8)
        params.append(contentsOf: session.description.utf8)
        params.append(contentsOf: #"","event":"#.utf8)
        params.append(event.json)
        params.append(UInt8(ascii: "}"))
        return params
    }
}

// The client side of the protocol: every request a client can make, answered on the host actor.
extension HostCore {
    /// Takes a new connection and serves it until it closes. Local clients (this user's own, checked
    /// by `PeerVerifier`) and SSH bridges are the owner; paired devices get what their pairing grants.
    public func accept(_ stream: any ByteStream, grants: ClientGrants = .owner) {
        let id = ClientLink.ID()
        let peer = JSONRPCPeer(channel: stream, label: "client") { [weak self] event in
            await self?.receive(event, fromClient: id)
        }
        let client = ClientLink(id: id, peer: peer, grants: grants)
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
            if appUpdateClient == id {
                appUpdateClient = nil
            }
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
        } catch let error as AgentLaunch.Failure {
            try? client.peer.respond(to: requestID, error: error.rpcError)
        } catch let error as DecodingError {
            try? client.peer.respond(to: requestID, error: .invalidParams(error))
        } catch {
            try? client.peer.respond(to: requestID, error: RPCError(code: -32000, message: error.localizedDescription))
        }
    }

    /// Handles one request. `reply` must be called, once, in the same actor turn as the state the
    /// result describes, so nothing slips in between (see `attach`).
    private func answer(
        _ message: JSONRPCPeer.Message, from client: ClientLink, reply: (any Encodable & Sendable) throws -> Void
    ) async throws {
        typealias Method = HostProtocol.Method
        switch message.method {
        case Method.initialize:
            let params = try message.params(as: InitializeParams.self)
            client.info = params.clientInfo
            try reply(info)
        case Method.syncAgents:
            // What a host launches is its owner's call, never a paired device's.
            guard client.grants.isLocal else { throw HostError.notAuthorized("change the agents this host runs") }
            let params = try message.params(as: SyncAgentsParams.self)
            try syncAgents(params.agents, refreshEnvironment: params.refreshEnvironment)
            try reply(EmptyMessage())
        case Method.listAgents:
            try reply(hostAgents)
        case Method.startAgent:
            try reply(try await startAgent(try message.params(as: AgentParams.self).agentID))
        case Method.stopAgent:
            try reply(try stopAgent(try message.params(as: AgentParams.self).agentID))
        case Method.restartAgent:
            try reply(try await restartAgent(try message.params(as: AgentParams.self).agentID))
        case Method.authenticateAgent:
            try reply(try await authenticateAgent(try message.params(as: AuthenticateAgentParams.self)))
        case Method.listAgentSessions:
            try reply(try await listAgentSessions(try message.params(as: ListAgentSessionsParams.self)))
        case Method.deleteAgentSession:
            try await deleteAgentSession(try message.params(as: DeleteAgentSessionParams.self))
            try reply(EmptyMessage())
        case Method.listSessions:
            try reply(
                sessions.values.map(\.summary).sorted {
                    ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
                })
        case Method.newSession:
            let params = try message.params(as: NewSessionParams.self)
            try reply(try await newSession(params, follower: params.attach ? client : nil))
        case Method.openSession:
            let params = try message.params(as: OpenSessionParams.self)
            try reply(try await openSession(params, follower: params.attach ? client : nil))
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
        case Method.respondQuestion:
            try respondQuestion(try message.params(as: RespondQuestionParams.self))
            try reply(EmptyMessage())
        case Method.runHidden:
            try reply(RunHiddenResult(output: try await runHidden(try message.params(as: RunHiddenParams.self))))
        case Method.setConfigOption:
            try await setConfigOption(try message.params(as: SetConfigOptionParams.self))
            try reply(EmptyMessage())
        case Method.updateQueued:
            try updateQueued(try message.params(as: QueueItemParams.self))
            try reply(EmptyMessage())
        case Method.removeQueued:
            try removeQueued(try message.params(as: QueueItemParams.self))
            try reply(EmptyMessage())
        case Method.restoreQueued:
            try restoreQueued(try message.params(as: RestoreQueuedParams.self))
            try reply(EmptyMessage())
        case Method.moveQueued:
            try moveQueued(try message.params(as: MoveQueuedParams.self))
            try reply(EmptyMessage())
        case Method.sendQueuedNow:
            try await sendQueuedNow(try message.params(as: QueueItemParams.self))
            try reply(EmptyMessage())
        case Method.setMCPServers:
            try setMCPServers(try message.params(as: SetMCPServersParams.self))
            try reply(EmptyMessage())
        case Method.closeSession:
            let params = try message.params(as: CloseSessionParams.self)
            try await closeSession(params.sessionID, closeInAgent: params.closeInAgent)
            try reply(EmptyMessage())
        case Method.listActivity:
            let params = try message.params(as: ListActivityParams.self)
            try reply(try store.activity(after: params.after, limit: min(params.limit, 1_000)))
        case Method.listPlugins:
            try reply(try listPlugins())
        case Method.pluginAsset:
            try reply(try pluginAsset(try message.params(as: PluginAssetParams.self)))
        case Method.setPluginEnabled:
            try reply(try setPluginEnabled(try message.params(as: SetPluginEnabledParams.self), by: client))
        case Method.updateStatus:
            try reply(updateStatus(for: client))
        case Method.updateCheck:
            checkForUpdate()
            try reply(updateStatus(for: client))
        case Method.updateInstall:
            try installUpdate(try message.params(as: HostUpdateInstallParams.self).when, by: client)
            try reply(updateStatus(for: client))
        case Method.updateReport:
            try receiveUpdateReport(try message.params(as: HostUpdateStatusMessage.self).status, from: client)
            try reply(EmptyMessage())
        case Method.shutdown:
            // Devices restart a host only through `update/install`, which installs a signed release.
            guard client.grants.isLocal else { throw HostError.notAuthorized("stop or restart the host") }
            try reply(EmptyMessage())
            let params = try message.params(as: ShutdownParams.self)
            await shutdown(stopAgents: params.stopAgents, immediately: params.immediately)
        default:
            throw RPCError.methodNotFound(message.method)
        }
    }

    /// Replays what the client hasn't seen as notifications, then answers, all in one actor turn:
    /// the client applies the replay, then live events, with nothing missed or doubled. A session
    /// the agent doesn't have loaded (after a restart) starts loading; its replay streams in live.
    private func attach(
        _ params: AttachParams, client: ClientLink, reply: (any Encodable & Sendable) throws -> Void
    ) throws {
        let session = try session(params.sessionID)
        let afterSeq = params.epoch == epoch ? params.afterSeq : nil
        client.send(session.events(after: afterSeq), of: session.id)
        session.subscribers.insert(client.id)
        client.attached.insert(session.id)
        try reply(AttachResult(summary: session.summary))
        if session.turn == nil {
            loadInBackground(session)
        }
    }
}
