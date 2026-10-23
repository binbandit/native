import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import Native

/// Holds session creation so navigation and retries can be checked against real host messages.
private actor QuickEntryHost: HostTransport {
    nonisolated var displayName: String { "Quick Entry fixture" }
    var peer: JSONRPCPeer?
    var pending: (RequestID, NewSessionParams)?
    var created = 0
    var prompts: [String] = []
    let agent = HostAgent(id: "fake", name: "Fake Agent", state: .ready)

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
            try peer.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
        case HostProtocol.Method.startAgent:
            try peer.respond(to: id, with: agent)
        case HostProtocol.Method.newSession:
            pending = (id, try message.params(as: NewSessionParams.self))
        case HostProtocol.Method.prompt:
            prompts.append(try message.params(as: PromptParams.self).text)
            try peer.respond(to: id, with: PromptResult(delivery: .prompted))
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
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

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
@MainActor
private struct QuickEntryRegression {
    static func main() async {
        do {
            // The switch is process-local, preserving the isolated instance's saved preferences.
            var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["experiment.NativeComposeTask"] = true
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            try await check()
            print("PASS: Quick Entry preserves drafts, selection, context, expansion and failed starts")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func check() async throws {
        let host = QuickEntryHost()
        let client = NativeHostClient(transport: host, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "quick-entry-fixture", name: "Quick Entry fixture",
            agents: [AgentManifest(id: "fake", name: "Fake Agent", command: "/usr/bin/true")])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil)
        app.connectHost(client: client)
        await app.followHost()
        _ = await app.checkForAgents()
        let folder = FileManager.default.temporaryDirectory.appending(path: "quick-entry-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = app.projects.add(folder)
        app.focusProject(project.id)
        let entry = app.quickEntry
        app.showQuickEntry(selection: "first line\nsecond line")
        entry.draft = "Keep this draft"
        let message = entry.message
        try require(message.hasSuffix("> first line\n> second line"), "Selection was not quoted")
        entry.dismiss()
        app.showQuickEntry(selection: "Do not replace retained context")
        try require(entry.message == message, "Reopening replaced the draft or context")
        let createdWhileDrafting = await host.created
        try require(app.startingTasks.isEmpty && createdWhileDrafting == 0, "Drafting created a task")

        app.startQuickEntry(open: false)
        guard let background = entry.lastStartedTask else { throw CheckFailure("No background start") }
        try require(app.selection != background.id, "Background start changed selection")
        try require(!entry.isPresented && entry.draft.isEmpty && entry.context == nil, "Start did not clear the panel")
        try await wait { await host.pending != nil }
        app.focusProject(project.id)
        let selectedWhileStarting = app.selection
        try await host.complete()
        try await wait { await host.prompts.count == 1 }
        try require(app.selection == selectedWhileStarting, "Background completion stole selection")
        try require(await host.prompts == [message], "The first message lost its selection context")
        app.openQuickEntryTask()
        try require(app.selection == background.openedSession, "Open did not find the completed task")

        app.showQuickEntry()
        entry.draft = "Start and open"
        app.startQuickEntry(open: true)
        guard let foreground = app.startingTasks.first else { throw CheckFailure("No foreground start") }
        try require(app.selection == foreground.id, "Start and open did not select its placeholder")
        try await wait { await host.pending != nil }
        try await host.complete()
        try await wait { await host.prompts.count == 2 }
        try require(app.selection == foreground.openedSession, "Foreground completion did not select the task")

        app.showQuickEntry()
        entry.draft = "Expand without sending"
        app.expandQuickEntry()
        try await wait { await host.pending != nil }
        try await host.complete()
        try await wait { app.startingTasks.isEmpty }
        try require(app.selection.flatMap(app.session)?.draft == "Expand without sending", "Expand lost the draft")
        try require(await host.prompts.count == 2, "Expand submitted the draft")

        app.showQuickEntry()
        entry.draft = "Retry me"
        app.startQuickEntry(open: false)
        guard let failed = entry.lastStartedTask else { throw CheckFailure("No failing start") }
        try await wait { await host.pending != nil }
        try await host.complete(failing: true)
        try await wait { failed.failure != nil }
        try require(failed.draft == "Retry me", "Failed startup lost the message")
        let retry = Task { await app.retry(failed) }
        try await wait { await host.pending != nil }
        try await host.complete()
        await retry.value
        try await wait { await host.prompts.count == 3 }
        try require(await host.prompts.last == "Retry me", "Retry did not send the retained message")

        app.showQuickEntry()
        entry.draft = "Keep while unavailable"
        entry.project = nil
        app.startQuickEntry(open: false)
        try require(entry.isPresented && entry.picker == .project, "Missing project did not stay editable")
        entry.project = project.id
        entry.device = .remote(NativeHostProtocol.HostID())
        app.startQuickEntry(open: false)
        try require(entry.isPresented && entry.picker == .device, "Unavailable device did not stay editable")
        entry.device = .thisMac
        try FileManager.default.removeItem(at: folder)
        app.startQuickEntry(open: false)
        try require(entry.isPresented && entry.failure != nil, "Missing folder did not stay editable")
        try require(entry.draft == "Keep while unavailable", "Validation discarded the draft")
        try require(app.startingTasks.isEmpty, "Validation created a placeholder")
        await client.stop()
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message) }
    }

    static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw CheckFailure("Timed out waiting for the expected state") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
