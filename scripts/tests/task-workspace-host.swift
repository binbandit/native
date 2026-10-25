import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

/// Real host wire messages, with controllable preparation and prompt replies.
actor WorkspaceTestHost: HostTransport {
    nonisolated var displayName: String { "Workspace fixture" }
    private var peer: JSONRPCPeer?
    private var counter = 0
    private var failNew = false
    private var holdNew = false
    private var failClose = false
    private var resetsEffort = false
    private var settings: [HostSessionID: (model: String, effort: String, sequence: Int)] = [:]
    private var pendingNew: JSONRPCPeer.Message?
    private var summaries: [HostSessionSummary] = []
    private let idPrefix: String
    private(set) var closed: [HostSessionID] = []
    private(set) var prompts: [PromptParams] = []
    private(set) var configChanges: [SetConfigOptionParams] = []
    var hasPendingNew: Bool { pendingNew != nil }
    var newSessionCount: Int { counter }

    init(idPrefix: String = "task") { self.idPrefix = idPrefix }

    func configure(fail: Bool = false, hold: Bool = false, failClose: Bool = false, resetEffort: Bool = false) {
        failNew = fail
        holdNew = hold
        self.failClose = failClose
        resetsEffort = resetEffort
    }

    func releaseNew() throws {
        holdNew = false
        if let pendingNew { try receive(pendingNew) }
        pendingNew = nil
    }

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "workspace-host"), label: "workspace-host") {
            [weak self] event in
            if case .request(let message) = event {
                Task {
                    do { try await self?.receive(message) } catch {
                        print("FAIL: fixture host could not answer a request")
                        exit(1)
                    }
                }
            }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "workspace-client")
    }

    private func receive(_ message: JSONRPCPeer.Message) throws {
        guard let id = message.id, let peer else { return }
        let agent = HostAgent(id: "workspace-fake", name: "Fixture", state: .ready)
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
        case HostProtocol.Method.startAgent:
            try peer.respond(to: id, with: agent)
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: summaries)
        case HostProtocol.Method.listAgentSessions:
            try peer.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
        case HostProtocol.Method.newSession:
            if holdNew { pendingNew = message; return }
            if failNew {
                try peer.respond(to: id, error: RPCError(code: -32603, message: "Fixture cannot open the folder"))
                return
            }
            counter += 1
            let params = try message.params(as: NewSessionParams.self)
            let task = params.sessionID ?? HostSessionID()
            settings[task] = ("small", "low", 1)
            let options = configOptions(model: "small", effort: "low")
            try peer.notify(
                HostProtocol.Method.sessionEvent,
                SessionEventNotification(sessionID: task, event: HostEvent(seq: 1, payload: .update(options))))
            let summary = HostSessionSummary(
                id: task, agentID: agent.id, agentName: agent.name, agentSessionID: SessionID("\(idPrefix)-\(counter)"),
                cwd: params.cwd, phase: .idle)
            summaries.append(summary)
            try peer.notify(HostProtocol.Method.sessionChanged, SessionChangedNotification(summary: summary))
            try peer.respond(to: id, with: summary)
        case HostProtocol.Method.setConfigOption:
            let change = try message.params(as: SetConfigOptionParams.self)
            configChanges.append(change)
            if resetsEffort, var current = settings[change.sessionID] {
                if change.configID == "model" { current.model = change.value; current.effort = "low" }
                if change.configID == "effort" { current.effort = change.value }
                current.sequence += 1
                settings[change.sessionID] = current
                try peer.notify(
                    HostProtocol.Method.sessionEvent,
                    SessionEventNotification(
                        sessionID: change.sessionID,
                        event: HostEvent(
                            seq: current.sequence,
                            payload: .update(configOptions(model: current.model, effort: current.effort)))))
            }
            try peer.respond(to: id, with: EmptyMessage())
        case HostProtocol.Method.closeSession:
            if failClose {
                try peer.respond(to: id, error: RPCError(code: -32603, message: "Fixture cannot close the task"))
                return
            }
            let sessionID = try message.params(as: CloseSessionParams.self).sessionID
            closed.append(sessionID)
            summaries.removeAll { $0.id == sessionID }
            try peer.notify(HostProtocol.Method.sessionClosed, SessionParams(sessionID: sessionID))
            try peer.respond(to: id, with: EmptyMessage())
        case HostProtocol.Method.prompt:
            prompts.append(try message.params(as: PromptParams.self))
            try peer.respond(to: id, with: PromptResult(delivery: .prompted))
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
    private func configOptions(model: String, effort: String) -> JSONValue {
        func option(_ id: String, _ category: String, _ current: String, _ choices: [String]) -> JSONValue {
            .object([
                "id": .string(id), "name": .string(id), "category": .string(category),
                "type": .string("select"), "currentValue": .string(current),
                "options": .array(choices.map { .object(["value": .string($0), "name": .string($0)]) }),
            ])
        }
        var options = [option("model", "model", model, ["small", "large"])]
        if resetsEffort { options.append(option("effort", "thought_level", effort, ["low", "high"])) }
        return .object(["sessionUpdate": .string("config_option_update"), "configOptions": .array(options)])
    }

}
