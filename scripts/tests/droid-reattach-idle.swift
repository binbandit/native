import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import Native
@testable import NativeLink

// A paired host's task while this Mac is away from it (asleep, off the network, the host's gateway
// off): the turn ends, or asks for an approval, while nothing here is connected. Once the link is
// back the task shows the host's state, its transcript has what it missed exactly once, and plugins
// hear each event once. The host is a fake process behind a fake transport that can go offline.

private struct ReattachFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// One host process: a session's event log and summary. Like the real host, it sends a session's
/// events to the clients following it and every summary change to every connected client, so a
/// client that is away when the session changes hears nothing of it.
private actor AwayHost {
    let hostID = HostID()
    let epoch = UUID()
    private(set) var summary: HostSessionSummary
    private(set) var log: [HostEvent] = []
    private var link: AwayLink?

    init(session: String) {
        summary = HostSessionSummary(
            id: HostSessionID(), agentID: "fixture", agentName: "Fixture", agentSessionID: SessionID(session),
            cwd: "/fixture/repo", title: "Away task", phase: .idle)
    }

    func connect(_ link: AwayLink) { self.link = link }

    func append(_ payload: HostEvent.Payload) async {
        let event = HostEvent(seq: (log.last?.seq ?? 0) + 1, payload: payload)
        log.append(event)
        await link?.send(event, of: summary.id)
    }

    func change(_ body: @Sendable (inout HostSessionSummary) -> Void) async {
        body(&summary)
        await link?.publish(summary)
    }

    /// What a client attaching after `seq` of `epoch` hasn't seen: everything from another run.
    func events(after seq: Int?, epoch: UUID?) -> [HostEvent] {
        guard epoch == self.epoch, let seq else { return log }
        return log.filter { $0.seq > seq }
    }
}

/// The pairing's transport. Offline, the connection is gone and connecting fails, as it does for a
/// Mac asleep or a host whose gateway is off.
private actor AwayLink: HostTransport {
    nonisolated var displayName: String { "Away fixture" }
    let host: AwayHost
    private var peer: JSONRPCPeer?
    private var isOffline = false
    private(set) var attaches = 0

    init(host: AwayHost) { self.host = host }

    func goOffline() {
        isOffline = true
        peer?.close()
        peer = nil
    }

    func goOnline() { isOffline = false }

    func connect() async throws -> any ByteStream {
        guard !isOffline else { throw ReattachFailure("The host isn't reachable") }
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "away-host"), label: "away-host") {
            [weak self] event in
            if case .request(let message) = event {
                Task {
                    do { try await self?.receive(message) } catch {
                        print("FAIL: fixture request \(message.method): \(error)")
                        exit(1)
                    }
                }
            }
        }
        self.peer = peer
        peer.start()
        await host.connect(self)
        return ByteChannel.socket(clientEnd, label: "away-client")
    }

    func send(_ event: HostEvent, of id: HostSessionID) {
        try? peer?.notify(HostProtocol.Method.sessionEvent, SessionEventNotification(sessionID: id, event: event))
    }

    func publish(_ summary: HostSessionSummary) {
        try? peer?.notify(HostProtocol.Method.sessionChanged, SessionChangedNotification(summary: summary))
    }

    private func receive(_ message: JSONRPCPeer.Message) async throws {
        guard let id = message.id, let peer else { return }
        switch message.method {
        case HostProtocol.Method.initialize:
            try peer.respond(
                to: id,
                with: HostInfo(
                    protocolVersion: HostProtocol.version, hostID: host.hostID, machineName: displayName,
                    hostInfo: PeerInfo(name: "Fixture", version: "1", build: "1"), epoch: host.epoch,
                    processID: 1, startedAt: .now, channel: "tests"))
        case HostProtocol.Method.listAgents:
            let initialize: JSONValue = .object([
                "protocolVersion": .number(1), "agentCapabilities": .object(["loadSession": .bool(true)]),
            ])
            let agent = HostAgent(id: "fixture", name: "Fixture", state: .ready, initialize: initialize)
            try peer.respond(to: id, with: [agent])
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: [await host.summary])
        case HostProtocol.Method.openSession:
            let summary = await host.summary
            for event in await host.events(after: nil, epoch: nil) { send(event, of: summary.id) }
            try peer.respond(to: id, with: summary)
        case HostProtocol.Method.attach:
            attaches += 1
            let params = try message.params(as: AttachParams.self)
            for event in await host.events(after: params.afterSeq, epoch: params.epoch) {
                send(event, of: params.sessionID)
            }
            try peer.respond(to: id, with: AttachResult(summary: await host.summary))
        case HostProtocol.Method.respondPermission, HostProtocol.Method.cancel, HostProtocol.Method.detach,
            HostProtocol.Method.configureTitles:
            try peer.respond(to: id, with: EmptyMessage())
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
}

/// Counts the session events plugins hear (`AppModel.start` hands them on), to catch any told twice.
@MainActor
private final class ReattachPluginLog {
    private var heard: [String] = []

    func hear(_ event: SessionEvent) {
        switch event {
        case .turnEnded: heard.append("turnEnded")
        case .turnFailed: heard.append("turnFailed")
        case .permissionRequested: heard.append("permissionRequested")
        default: break
        }
    }

    func count(_ name: String) -> Int { heard.filter { $0 == name }.count }
}

@main
@MainActor
private struct DroidReattachIdleRegression {
    /// What went wrong in the checks so far. Each case runs whatever an earlier one found, so a build
    /// without the fix shows every failure at once.
    static var failures: [String] = []

    static func main() async {
        do { try await run() } catch {
            failures.append("\(error)")
        }
        for failure in failures { print("FAIL: \(failure)") }
        exit(failures.isEmpty ? 0 : 1)
    }

    /// A step the rest depends on: stops the run when it fails.
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ReattachFailure(message) }
    }

    static func wait(_ what: String, timeout: Duration = .seconds(10), _ condition: () async -> Bool) async throws {
        guard await settles(within: timeout, condition) else { throw ReattachFailure("Timed out: \(what)") }
    }

    /// A check: records a failure and carries on.
    static func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    /// A check that may take a moment; returns whether it held.
    @discardableResult
    static func expect(_ what: String, timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
        let held = await settles(within: timeout, condition)
        check(held, "Timed out: \(what)")
        return held
    }

    private static func settles(within timeout: Duration, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    static func chunk(_ text: String) -> HostEvent.Payload {
        .update(
            .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": .object(["type": .string("text"), "text": .string(text)]),
            ]))
    }

    static func permission(_ toolCallID: String) -> HostEvent.Payload {
        .permissionRequested(
            toolCallID: toolCallID,
            request: .object([
                "sessionId": .string("task"),
                "toolCall": .object(["toolCallId": .string(toolCallID), "title": .string("Write notes.txt")]),
                "options": .array([
                    .object(["optionId": .string("allow"), "name": .string("Allow"), "kind": .string("allow_once")])
                ]),
            ]))
    }

    /// A transcript's items without their ids: what a duplicated or missing event changes.
    static func shape(_ items: [TranscriptItem]) -> [String] {
        items.map { item in
            if case .message(let message) = item {
                "\(message.role): \(message.text)"
            } else {
                String(String(describing: item).prefix { $0 != "(" })
            }
        }
    }

    static func run() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "reattach-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "fixture", name: "Fixture",
            agents: [AgentManifest(id: "fixture", name: "Fixture", command: "/usr/bin/true")])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil,
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appending(path: "hosts"))))
        _ = app.runtimes.sync()
        // What `AppModel.start` would broadcast to plugins, read here instead.
        let plugins = ReattachPluginLog()
        guard
            let events = Mirror(reflecting: app).children.first(where: { $0.label == "pluginEvents" })?.value
                as? AsyncStream<SessionEvent>
        else { throw ReattachFailure("No plugin events") }
        Task { for await event in events { plugins.hear(event) } }
        // The app's wiring (AppModel.startRemoteHosts), without reaching for the network.
        app.hosts.onEvent = { _, event in
            app.sessions.handle(event)
            if case .sessionChanged = event { app.indexRemoteSessions() }
        }
        app.hosts.onRefreshed = { host in Task { await app.hostConnected(host) } }
        let project = app.projects.add(URL(filePath: "/fixture/repo"))

        let process = AwayHost(session: "task")
        let link = AwayLink(host: process)
        let client = NativeHostClient(transport: link, clientInfo: PeerInfo(name: "Fixture", version: "1", build: "1"))
        let remote = app.hosts.add(
            PairedHost(
                result: LinkPairingResult(
                    hostID: process.hostID, hostKey: LinkIdentity().publicKey, hostName: "Fixture", deviceID: UUID(),
                    grants: LinkGrants(), addresses: []), identity: LinkIdentity()))
        remote.start(using: client)
        defer { Task { await client.stop() } }
        let id = await process.summary.id
        let key = SessionKey(agent: .init(rawValue: "fixture"), id: SessionID("task"))
        func caughtUp(_ session: SessionModel) async -> Bool {
            var mirror = SessionMirror()
            mirror.apply(await process.log)
            return shape(session.state.items) == shape(mirror.state.items)
        }
        /// Takes the link down, runs `meanwhile` on the host, and brings the link back. Returns when
        /// the link went down and what the host's "Last connected" said while it was.
        @discardableResult
        func away(_ meanwhile: () async -> Void) async throws -> (left: Date, lastConnected: Date?) {
            let left = Date.now
            await link.goOffline()
            try await wait("the link drops") { !remote.isOnline }
            let lastConnected = remote.lastConnected
            await meanwhile()
            await link.goOnline()
            try await wait("the link is back", timeout: .seconds(20)) { remote.isOnline }
            return (left, lastConnected)
        }
        /// Prints `message` when no check failed since `before` failures.
        func pass(_ message: String, since before: Int) {
            if failures.count == before { print("PASS: \(message)") }
        }

        // A task opened on the host, an earlier turn finished.
        await process.append(.reset(loading: false))
        await process.append(.prompt(PromptEcho(text: "hello")))
        await process.append(chunk("Hi"))
        await process.append(.turnEnded(stopReason: "end_turn"))
        await process.change { $0.lastStopReason = "end_turn" }
        try await wait("first connection") {
            remote.runtime(.init(rawValue: "fixture")) != nil && !remote.sessions.isEmpty
        }
        app.setCheckout(project.path, of: project.id, on: remote.id)
        try require(await app.loadRemoteSession(key), "Remote task did not open")
        guard let session = app.sessions.session(key) else { throw ReattachFailure("No model for the task") }

        // A turn starts while connected.
        await process.change { $0.phase = .prompting }
        await process.append(.prompt(PromptEcho(text: "write the notes")))
        await process.append(chunk("Writing"))
        try await wait("the turn shows working") { session.taskStatus == .working }

        // It ends while this Mac is away.
        var before = failures.count
        let trip = try await away {
            await process.append(chunk(" done"))
            await process.append(.turnEnded(stopReason: "end_turn"))
            await process.change {
                $0.phase = .idle
                $0.lastStopReason = "end_turn"
            }
        }
        await expect("the transcript catches up once") { await caughtUp(session) }
        await expect("the task shows the finished turn after reconnecting") { session.taskStatus == .done }
        check(session.phase == .idle, "The task still reads working: phase \(session.phase)")
        check(remote.session(id)?.phase == .idle, "The host's session list still reads working")
        pass("a turn that ends while away shows finished after reconnecting, its events once", since: before)

        before = failures.count
        check(
            (trip.lastConnected ?? .distantPast) >= trip.left,
            "Last connected says when the connection began, not when it was lost")
        pass("Last connected says when the connection was lost", since: before)

        // Another turn asks for an approval while this Mac is away.
        before = failures.count
        try await away {
            await process.change {
                $0.phase = .prompting
                $0.needsApproval = true
            }
            await process.append(.prompt(PromptEcho(text: "and commit")))
            await process.append(permission("call-1"))
        }
        await expect("the transcript catches up once") { await caughtUp(session) }
        await expect("the task shows the approval after reconnecting") { session.taskStatus == .needsPermission }
        check(session.state.pendingPermissions.count == 1, "The approval isn't shown once")
        check(session.phase == .prompting, "The waiting turn doesn't read as running: phase \(session.phase)")
        pass("an approval asked while away shows after reconnecting", since: before)

        // Answered on the droid itself while away: the turn goes on, then fails.
        before = failures.count
        try await away {
            await process.append(.permissionResolved(toolCallID: "call-1", optionID: "allow"))
            await process.change { $0.needsApproval = false }
            await process.append(.turnFailed(message: "The agent stopped responding.", error: nil, retry: nil))
            await process.change {
                $0.phase = .idle
                $0.lastStopReason = "error"
            }
        }
        await expect("the transcript catches up once") { await caughtUp(session) }
        await expect("the task shows the failed turn after reconnecting") { session.taskStatus == .failed }
        check(session.state.pendingPermissions.isEmpty, "The answered approval is still shown")
        pass("a turn that fails while away shows failed after reconnecting", since: before)

        before = failures.count
        await expect("plugins hear the turn end") { plugins.count("turnEnded") == 1 }
        await expect("plugins hear the failed turn") { plugins.count("turnFailed") == 1 }
        check(plugins.count("permissionRequested") == 1, "The approval was announced twice")
        check(plugins.count("turnEnded") == 1, "The turn end was announced twice")
        check(await link.attaches == 3, "Each reconnect should attach the task once")
        pass("plugins hear each event once", since: before)
    }
}
