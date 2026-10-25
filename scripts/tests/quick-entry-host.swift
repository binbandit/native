import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

/// Holds session creation so navigation and retries can be checked against real host messages.
actor QuickEntryHost: HostTransport {
    nonisolated var displayName: String { "Quick Entry fixture" }
    var peer: JSONRPCPeer?
    var pending: (RequestID, NewSessionParams)?
    var created = 0
    var prompts: [String] = []
    var holdsListing = false
    var rejectsPrompt = false
    func rejectNextPrompt() { rejectsPrompt = true }
    var listingRequest: RequestID?
    let agent = HostAgent(
        id: "fake", name: "Fake Agent", state: .ready,
        initialize: .object([
            "protocolVersion": .number(1),
            "agentCapabilities": .object(["sessionCapabilities": .object(["list": .object([:])])]),
        ]))

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(
            channel: ByteChannel.socket(hostEnd, label: "quick-entry-host"), label: "quick-entry-host"
        ) {
            [weak self] event in
            if case .request(let message) = event {
                Task {
                    do { try await self?.receive(message) } catch { print("Fixture request failed: \(error)") }
                }
            }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "quick-entry-client")
    }

    func receive(_ message: JSONRPCPeer.Message) throws {
        guard let id = message.id, let peer else { return }
        switch message.method {
        case HostProtocol.Method.initialize:
            try peer.respond(
                to: id,
                with: HostInfo(
                    protocolVersion: HostProtocol.version, hostID: HostID(), machineName: displayName,
                    hostInfo: PeerInfo(name: "Native Host", version: "1", build: "1"), epoch: UUID(),
                    processID: 1, startedAt: .now, channel: "tests"))
        case HostProtocol.Method.syncAgents:
            try peer.respond(to: id, with: EmptyMessage())
        case HostProtocol.Method.listAgents:
            try peer.respond(to: id, with: [agent])
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: [HostSessionSummary]())
        case HostProtocol.Method.listAgentSessions:
            if holdsListing {
                listingRequest = id
            } else {
                try peer.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
            }
        case HostProtocol.Method.startAgent:
            try peer.respond(to: id, with: agent)
        case HostProtocol.Method.newSession:
            pending = (id, try message.params(as: NewSessionParams.self))
        case HostProtocol.Method.prompt:
            if rejectsPrompt {
                rejectsPrompt = false
                try peer.respond(to: id, error: RPCError(code: -32603, message: "Fixture prompt rejection"))
                return
            }
            let prompt = try message.params(as: PromptParams.self)
            prompts.append(prompt.text)
            try peer.notify(
                HostProtocol.Method.sessionEvent,
                SessionEventNotification(
                    sessionID: prompt.sessionID,
                    event: HostEvent(seq: 1, payload: .prompt(PromptEcho(text: prompt.text, steered: false)))))
            try peer.respond(to: id, with: PromptResult(delivery: .prompted))
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }

    func holdListing() { holdsListing = true }

    func releaseListing() throws {
        holdsListing = false
        if let id = listingRequest {
            try peer?.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
        }
        listingRequest = nil
    }

    func complete(failing: Bool = false) throws {
        guard let (id, params) = pending, let peer else { throw CheckFailure("No pending session") }
        pending = nil
        if failing {
            try peer.respond(to: id, error: RPCError(code: -32603, message: "Fixture startup failure"))
        } else {
            created += 1
            try peer.respond(
                to: id,
                with: HostSessionSummary(
                    id: params.sessionID ?? HostSessionID(), agentID: "fake", agentName: "Fake Agent",
                    agentSessionID: SessionID("quick-entry-\(created)"), cwd: params.cwd, phase: .idle))
        }
    }
}
