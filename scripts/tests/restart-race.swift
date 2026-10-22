import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import Native

/// A host with a manually completed restart. Requests still use the real client and wire protocol.
private actor RestartHost: HostTransport {
    nonisolated var displayName: String { "Restart fixture" }
    var peer: JSONRPCPeer?
    var restartRequest: RequestID?
    var syncRequest: RequestID?
    var holdsSync = false
    var restartCount = 0
    var newTaskCount = 0
    var agent = HostAgent(id: "fake", name: "Fake Agent", state: .failed, problem: "Initial failure")

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "restart-host"), label: "restart-host") {
            [weak self] event in
            if case .request(let message) = event {
                Task {
                    do { try await self?.receive(message) } catch { print("Fixture request failed: \(error)") }
                }
            }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "restart-client")
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
            if holdsSync { syncRequest = id } else { try peer.respond(to: id, with: EmptyMessage()) }
        case HostProtocol.Method.listAgents:
            try peer.respond(to: id, with: [agent])
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: [HostSessionSummary]())
        case HostProtocol.Method.listAgentSessions:
            try peer.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
        case HostProtocol.Method.startAgent:
            try peer.respond(to: id, with: agent)
        case HostProtocol.Method.restartAgent:
            restartCount += 1
            restartRequest = id
            agent.state = .starting
            agent.problem = nil
            try peer.notify(HostProtocol.Method.agentChanged, AgentChangedNotification(agent: agent))
        case HostProtocol.Method.newSession:
            newTaskCount += 1
            let params = try message.params(as: NewSessionParams.self)
            try peer.respond(
                to: id,
                with: HostSessionSummary(
                    id: params.sessionID ?? HostSessionID(), agentID: "fake", agentName: "Fake Agent",
                    agentSessionID: SessionID("task-\(newTaskCount)"), cwd: params.cwd, phase: .idle))
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }

    func holdSynchronization() { holdsSync = true }

    func releaseSynchronization() throws {
        holdsSync = false
        if let id = syncRequest { try peer?.respond(to: id, with: EmptyMessage()) }
        syncRequest = nil
    }

    func completeRestart(failing: Bool, requestFailure: Bool = false) throws {
        guard let peer, let id = restartRequest else { throw CheckFailure("No pending restart") }
        restartRequest = nil
        if requestFailure {
            try peer.respond(to: id, error: RPCError(code: -32603, message: "The test agent could not initialize."))
            return
        }
        agent.state = failing ? .failed : .ready
        agent.problem = failing ? "The test agent could not initialize." : nil
        try peer.notify(HostProtocol.Method.agentChanged, AgentChangedNotification(agent: agent))
        try peer.respond(to: id, with: agent)
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
@MainActor
private struct RestartRaceRegression {
    static func main() async {
        do {
            try await check(failing: false, discard: false)
            try await check(failing: true, discard: false)
            try await check(failing: true, discard: false, requestFailure: true)
            try await check(failing: false, discard: true)
            print("PASS: task startup waits for restart; failure, retry, draft and discard are preserved")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func check(failing: Bool, discard: Bool, requestFailure: Bool = false) async throws {
        let host = RestartHost()
        let client = NativeHostClient(transport: host, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "restart-fixture", name: "Restart fixture",
            agents: [AgentManifest(id: "fake", name: "Fake Agent", command: "/usr/bin/true")])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil)
        app.connectHost(client: client)
        await app.followHost()
        _ = await app.checkForAgents()
        let folder = FileManager.default.temporaryDirectory.appending(path: "restart-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = app.projects.add(folder)
        let agent = AgentDefinition.ID(rawValue: "fake")
        await host.holdSynchronization()
        let restart = Task { await app.restart(agent) }
        try await wait { await host.syncRequest != nil }
        let start = Task { await app.newSession(in: project.id, with: agent) }
        try await wait { app.startingTasks.first?.folder != nil }
        guard let task = app.startingTasks.first else { throw CheckFailure("No starting task") }
        task.draft = "Keep this draft"
        // The host is held indefinitely, so a premature failure is deterministic.
        try await Task.sleep(for: .milliseconds(100))
        guard task.failure == nil, await host.newTaskCount == 0 else {
            throw CheckFailure("Task failed or opened before restart completed: \(task.failure?.message ?? "opened")")
        }
        try await host.releaseSynchronization()
        try await wait { app.runtime(agent)?.status == .starting }
        let duplicateRestart = Task { await app.restart(agent) }
        try await Task.sleep(for: .milliseconds(100))
        guard task.failure == nil, await host.newTaskCount == 0 else {
            throw CheckFailure("Task did not wait for agent initialization")
        }
        if discard { app.discard(task) }
        try await host.completeRestart(failing: failing, requestFailure: requestFailure)
        await restart.value
        await duplicateRestart.value
        await start.value
        if discard {
            guard app.startingTasks.isEmpty, await host.newTaskCount == 0 else {
                throw CheckFailure("Discarded task still opened")
            }
        } else if failing {
            guard task.failure?.message.contains("could not initialize") == true, task.draft == "Keep this draft" else {
                throw CheckFailure("Restart diagnostic or draft was lost")
            }
            let retry = Task { await app.retry(task) }
            try await wait { app.runtime(agent)?.status == .starting }
            guard task.failure == nil, task.folder == folder else { throw CheckFailure("Retry lost its workspace") }
            try await host.completeRestart(failing: false)
            await retry.value
            try opened(app, draft: "Keep this draft")
            guard await host.restartCount == 2 else { throw CheckFailure("Retry did not restart exactly once") }
        } else {
            try opened(app, draft: "Keep this draft")
            guard await host.restartCount == 1 else { throw CheckFailure("Task triggered another restart") }
        }
        await client.stop()
    }

    static func opened(_ app: AppModel, draft: String) throws {
        guard app.startingTasks.isEmpty, let key = app.selection, let task = app.session(key), task.draft == draft
        else {
            throw CheckFailure("Task did not open with its draft")
        }
    }

    static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw CheckFailure("Timed out waiting for the expected state") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
