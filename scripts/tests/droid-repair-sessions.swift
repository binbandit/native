import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import Native
@testable import NativeLink

// Paired-host tasks across a new pairing: the same host paired again, its removal undone, a pairing
// that drops or is replaced while it attaches, and pairings that must not inherit tasks (another
// key, an ended pairing, another host). Every pairing is a fake transport to a fake host process.

private struct RepairFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// One host process: its sessions' event logs, shared by every pairing's link to it.
private actor RepairHost {
    let hostID = HostID()
    let epoch = UUID()
    private(set) var summaries: [HostSessionSummary]
    private var logs: [HostSessionID: [HostEvent]] = [:]
    private var subscribers: [HostSessionID: [RepairLink]] = [:]
    /// Prompt request ids in the order the host accepted them; a repeat is answered, not accepted.
    private(set) var accepted: [UUID] = []

    init(session: String) {
        summaries = [
            HostSessionSummary(
                id: HostSessionID(), agentID: "fixture", agentName: "Fixture", agentSessionID: SessionID(session),
                cwd: "/fixture/repo", title: "Keep this title", phase: .idle)
        ]
    }

    func summary(_ id: HostSessionID) -> HostSessionSummary? { summaries.first { $0.id == id } }
    func summary(agentSessionID: SessionID) -> HostSessionSummary? {
        summaries.first { $0.agentSessionID == agentSessionID }
    }
    func log(of id: HostSessionID) -> [HostEvent] { logs[id] ?? [] }

    func setPhase(_ phase: HostSessionPhase, of id: HostSessionID) {
        if let index = summaries.firstIndex(where: { $0.id == id }) { summaries[index].phase = phase }
    }

    func log(_ payload: HostEvent.Payload, in id: HostSessionID) async {
        let event = HostEvent(seq: (logs[id]?.last?.seq ?? 0) + 1, payload: payload)
        logs[id, default: []].append(event)
        for link in subscribers[id] ?? [] { await link.send(event, of: id) }
    }

    /// Subscribes `link` and returns what it hasn't seen, in one step, as the real host does.
    func attach(_ link: RepairLink, to id: HostSessionID, after seq: Int?, epoch: UUID?) -> [HostEvent] {
        subscribers[id, default: []].removeAll { $0 === link }
        subscribers[id, default: []].append(link)
        let all = logs[id] ?? []
        guard epoch == self.epoch, let seq else { return all }
        return all.filter { $0.seq > seq }
    }

    func prompt(_ params: PromptParams) async -> PromptDelivery {
        guard !accepted.contains(params.requestID) else { return .prompted }
        accepted.append(params.requestID)
        await log(.prompt(PromptEcho(text: params.text, requestID: params.requestID)), in: params.sessionID)
        return .prompted
    }
}

/// One pairing's transport to the host, recording the requests that came through it.
private actor RepairLink: HostTransport {
    nonisolated var displayName: String { "Repair fixture" }
    let host: RepairHost
    private var peer: JSONRPCPeer?
    private(set) var calls: [String] = []
    private(set) var prompts: [UUID] = []
    /// The next attach sends two events of its replay, then the connection drops.
    private var dropsNextAttach = false
    /// The next attach waits until `releaseAttach()`.
    private var holdsNextAttach = false
    private(set) var isHoldingAttach = false
    private var heldAttach: CheckedContinuation<Void, Never>?
    /// Prompts are accepted but never answered.
    private var withholdsPromptAnswers = false

    init(host: RepairHost) { self.host = host }

    func configure(dropsNextAttach: Bool = false, holdsNextAttach: Bool = false, withholdsPromptAnswers: Bool = false) {
        self.dropsNextAttach = dropsNextAttach
        self.holdsNextAttach = holdsNextAttach
        self.withholdsPromptAnswers = withholdsPromptAnswers
    }

    func releaseAttach() {
        heldAttach?.resume()
        heldAttach = nil
    }

    func count(_ method: String) -> Int { calls.filter { $0 == method }.count }

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "repair-host"), label: "repair-host") {
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
        return ByteChannel.socket(clientEnd, label: "repair-client")
    }

    func send(_ event: HostEvent, of id: HostSessionID) {
        try? peer?.notify(HostProtocol.Method.sessionEvent, SessionEventNotification(sessionID: id, event: event))
    }

    private func receive(_ message: JSONRPCPeer.Message) async throws {
        guard let id = message.id, let peer else { return }
        calls.append(message.method)
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
            try peer.respond(to: id, with: await host.summaries)
        case HostProtocol.Method.openSession:
            let params = try message.params(as: OpenSessionParams.self)
            guard let summary = await host.summary(agentSessionID: params.agentSessionID) else {
                throw RepairFailure("Unknown open")
            }
            for event in await host.attach(self, to: summary.id, after: nil, epoch: nil) { send(event, of: summary.id) }
            try peer.respond(to: id, with: summary)
        case HostProtocol.Method.attach:
            let params = try message.params(as: AttachParams.self)
            if dropsNextAttach {
                dropsNextAttach = false
                for event in await host.log(of: params.sessionID).prefix(2) { send(event, of: params.sessionID) }
                peer.close()
                return
            }
            if holdsNextAttach {
                holdsNextAttach = false
                isHoldingAttach = true
                await withCheckedContinuation { heldAttach = $0 }
            }
            let replay = await host.attach(self, to: params.sessionID, after: params.afterSeq, epoch: params.epoch)
            for event in replay { send(event, of: params.sessionID) }
            guard let summary = await host.summary(params.sessionID) else { throw RepairFailure("Unknown attach") }
            // A held attach answers a client that has stopped by now.
            try? peer.respond(to: id, with: AttachResult(summary: summary))
        case HostProtocol.Method.prompt:
            let params = try message.params(as: PromptParams.self)
            prompts.append(params.requestID)
            let delivery = await host.prompt(params)
            guard !withholdsPromptAnswers else { return }
            try peer.respond(to: id, with: PromptResult(delivery: delivery))
        case HostProtocol.Method.respondPermission:
            let params = try message.params(as: RespondPermissionParams.self)
            await host.log(
                .permissionResolved(toolCallID: params.toolCallID, optionID: params.optionID), in: params.sessionID)
            try peer.respond(to: id, with: EmptyMessage())
        case HostProtocol.Method.cancel, HostProtocol.Method.updateQueued, HostProtocol.Method.detach,
            HostProtocol.Method.configureTitles:
            try peer.respond(to: id, with: EmptyMessage())
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
}

/// Counts the session events plugins hear (`AppModel.start` hands them on), to catch any told twice.
@MainActor
private final class RepairPluginLog {
    private var heard: [String] = []

    func hear(_ event: SessionEvent) {
        switch event {
        case .promptSent: heard.append("promptSent")
        case .turnEnded: heard.append("turnEnded")
        case .permissionRequested: heard.append("permissionRequested")
        default: break
        }
    }

    func count(_ name: String) -> Int { heard.filter { $0 == name }.count }
}

@main
@MainActor
private struct DroidRepairSessionsRegression {
    static func main() async {
        do { try await run() } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw RepairFailure(message) }
    }

    static func wait(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw RepairFailure("Timed out: \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
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
        let scratch = FileManager.default.temporaryDirectory.appending(path: "repair-\(UUID())")
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
        let plugins = RepairPluginLog()
        guard
            let events = Mirror(reflecting: app).children.first(where: { $0.label == "pluginEvents" })?.value
                as? AsyncStream<SessionEvent>
        else { throw RepairFailure("No plugin events") }
        Task { for await event in events { plugins.hear(event) } }
        // The app's wiring (AppModel.startRemoteHosts), without reaching for the network.
        app.hosts.onEvent = { _, event in
            app.sessions.handle(event)
            if case .sessionChanged = event { app.indexRemoteSessions() }
        }
        app.hosts.onRefreshed = { host in Task { await app.hostConnected(host) } }
        let project = app.projects.add(URL(filePath: "/fixture/repo"))

        let process = RepairHost(session: "task")
        let elsewhere = RepairHost(session: "other")
        let hostKey = LinkIdentity().publicKey
        let peerInfo = PeerInfo(name: "Fixture", version: "1", build: "1")
        func pairing(_ host: RepairHost, key: LinkPublicKey) -> PairedHost {
            PairedHost(
                result: LinkPairingResult(
                    hostID: host.hostID, hostKey: key, hostName: "Fixture", deviceID: UUID(), grants: LinkGrants(),
                    addresses: []), identity: LinkIdentity())
        }
        /// Pairs with `host` through a new link; `meanwhile` runs once the old client has stopped and
        /// before the new one connects.
        func pair(
            _ host: RepairHost, key: LinkPublicKey, configure: (RepairLink) async -> Void = { _ in },
            meanwhile: () async -> Void = {}
        ) async -> (RemoteHost, NativeHostClient, RepairLink) {
            let link = RepairLink(host: host)
            await configure(link)
            let client = NativeHostClient(transport: link, clientInfo: peerInfo)
            let remote = app.hosts.add(pairing(host, key: key))
            await meanwhile()
            remote.start(using: client)
            return (remote, client, link)
        }
        guard let id = await process.summaries.first?.id else { throw RepairFailure("No host session") }
        let key = SessionKey(agent: .init(rawValue: "fixture"), id: SessionID("task"))
        func caughtUp(_ session: SessionModel) async -> Bool {
            var mirror = SessionMirror()
            mirror.apply(await process.log(of: id))
            return shape(session.state.items) == shape(mirror.state.items)
        }

        // A task opened through the first pairing, with an approval waiting.
        await process.log(.reset(loading: false), in: id)
        await process.log(.prompt(PromptEcho(text: "hello")), in: id)
        await process.log(chunk("Hi"), in: id)
        await process.log(.turnEnded(stopReason: "end_turn"), in: id)
        let (first, clientA, linkA) = await pair(process, key: hostKey)
        try await wait("first connection") {
            first.runtime(.init(rawValue: "fixture")) != nil && !first.sessions.isEmpty
        }
        app.setCheckout(project.path, of: project.id, on: first.id)
        try require(await app.loadRemoteSession(key), "Remote task did not open")
        guard let session = app.sessions.session(key) else { throw RepairFailure("No model for the task") }
        try require(session.host?.client === clientA, "Task did not open on the first pairing")
        await process.log(permission("call-0"), in: id)
        try await wait("approval through the first pairing") { !session.state.pendingPermissions.isEmpty }

        // A task on another host, which keeps its own client throughout.
        let (other, clientZ, _) = await pair(elsewhere, key: LinkIdentity().publicKey)
        try await wait("other host") { other.runtime(.init(rawValue: "fixture")) != nil && !other.sessions.isEmpty }
        app.setCheckout(project.path, of: project.id, on: other.id)
        let otherKey = SessionKey(agent: .init(rawValue: "fixture"), id: SessionID("other"))
        try require(await app.loadRemoteSession(otherKey), "Other host's task did not open")
        guard let otherSession = app.sessions.session(otherKey) else { throw RepairFailure("No model on other host") }

        session.draft = "Keep this draft"
        app.selection = key
        let title = session.displayTitle
        let ids = session.state.items.map(\.id)

        // Pairing again during a turn, with a message in flight on the first pairing.
        await process.setPhase(.prompting, of: id)
        await linkA.configure(withholdsPromptAnswers: true)
        let sending = Task {
            try await session.submitToHost("sent while pairing", attachments: [], behavior: .queue, echo: true)
        }
        try await wait("message reaches the host") { await process.accepted.count == 1 }
        guard let inFlight = await linkA.prompts.first else { throw RepairFailure("No message in flight") }
        let (_, clientB, linkB) = await pair(
            process, key: hostKey,
            meanwhile: {
                // Answered on another device, and more of the turn, while no client here follows it.
                await process.log(.permissionResolved(toolCallID: "call-0", optionID: "allow"), in: id)
                await process.log(chunk(" and more"), in: id)
            })
        try await wait("task moves to the new pairing") { session.host?.client === clientB }
        try await wait("catches up through the new pairing") {
            let isCaughtUp = await caughtUp(session)
            return session.state.pendingPermissions.isEmpty && isCaughtUp
        }
        let delivery = try await sending.value
        try require(delivery == .prompted, "The message in flight wasn't delivered")
        try require(await process.accepted == [inFlight], "The message in flight was accepted twice")
        try require(await linkB.prompts == [inFlight], "The message in flight didn't go again through the new pairing")
        try require(app.sessions.session(key) === session, "Pairing again replaced the task's model")
        try require(session.draft == "Keep this draft" && app.selection == key, "Lost the draft or selection")
        try require(session.displayTitle == title, "Lost the title")
        try require(Array(session.state.items.map(\.id).prefix(ids.count)) == ids, "The transcript started over")
        try require(session.phase == .prompting, "The running turn isn't shown")
        for method in [HostProtocol.Method.newSession, HostProtocol.Method.openSession] {
            try require(await linkB.count(method) == 0, "Pairing again sent \(method)")
        }
        print("PASS: pairing again during a turn keeps the task and catches up once")

        // What the replaced client still had in hand doesn't reach the task.
        let stale = SessionMirror.Step(HostEvent(seq: 1_000, payload: chunk(" stale")))
        first.onEvent?(first, .sessionEvent(id, stale))
        try require(!shape(session.state.items).contains { $0.contains("stale") }, "A replaced client's event landed")

        // Send, approval, queue edit and Stop go through the new pairing only.
        let callsOnA = await linkA.calls.count
        await process.log(permission("call-1"), in: id)
        try await wait("approval through the new pairing") { !session.state.pendingPermissions.isEmpty }
        await session.choose(
            PermissionOption(optionId: "allow", name: "Allow", kind: .allowOnce), forToolCall: "call-1")
        _ = try await session.submitToHost("after pairing", attachments: [], behavior: .queue, echo: true)
        session.updateQueuedOnHost(UUID(), text: "edited")
        await session.cancelOnHost()
        try await wait("queue edit") { await linkB.count(HostProtocol.Method.updateQueued) == 1 }
        try require(
            await linkB.count(HostProtocol.Method.respondPermission) == 1, "Approval didn't reach the new pairing")
        try require(await linkB.count(HostProtocol.Method.cancel) == 1, "Stop didn't reach the new pairing")
        try require(await linkB.prompts.count == 2, "Send didn't reach the new pairing")
        try require(await process.accepted.count == 2, "A message was accepted twice")
        try require(await linkA.calls.count == callsOnA, "The replaced pairing still got requests")
        await process.setPhase(.idle, of: id)
        await process.log(.turnEnded(stopReason: "end_turn"), in: id)
        try await wait("turn end") { await caughtUp(session) }
        print("PASS: send, approval, queue edit and Stop reach only the new pairing")

        // Removing the host, then undoing it.
        guard let removed = app.hosts.remove(first.id) else { throw RepairFailure("Couldn't remove the host") }
        await process.log(chunk(" while removed"), in: id)
        app.hosts.restore(removed.paired, at: removed.index)
        guard let restored = app.hosts.host(first.id) else { throw RepairFailure("Undo didn't restore the host") }
        let linkC = RepairLink(host: process)
        let clientC = NativeHostClient(transport: linkC, clientInfo: peerInfo)
        restored.start(using: clientC)
        try await wait("undo moves the task") { session.host?.client === clientC }
        try await wait("catches up after undo") { await caughtUp(session) }
        print("PASS: removing the host and undoing it recovers the task")

        // The connection drops while the new pairing attaches; it attaches again by itself.
        let (_, clientD, linkD) = await pair(
            process, key: hostKey, configure: { await $0.configure(dropsNextAttach: true) })
        try await wait("task moves while the connection drops") { session.host?.client === clientD }
        try await wait("attaches again") { await linkD.count(HostProtocol.Method.attach) >= 2 }
        await process.log(chunk(" after the drop"), in: id)
        try await wait("events after the drop") { await caughtUp(session) }
        print("PASS: a connection lost while attaching recovers without duplicates")

        // Pairing again while the previous pairing's attach is still in flight.
        let (_, clientE, linkE) = await pair(
            process, key: hostKey, configure: { await $0.configure(holdsNextAttach: true) })
        try await wait("attach in flight") { await linkE.isHoldingAttach }
        try require(session.host?.client === clientE, "Task isn't on the pairing that's attaching")
        let (_, clientF, linkF) = await pair(process, key: hostKey)
        try await wait("newest pairing takes over") {
            let attaches = await linkF.count(HostProtocol.Method.attach)
            return session.host?.client === clientF && attaches == 1
        }
        await linkE.releaseAttach()
        await process.log(chunk(" final"), in: id)
        try await wait("events through the newest pairing") { await caughtUp(session) }
        try require(session.host?.client === clientF, "A stale attach took the task back")
        print("PASS: a second pairing while the first attaches keeps the newest")

        // Another key under the same host id never inherits the task; the right key still does.
        let (_, clientW, linkW) = await pair(process, key: LinkIdentity().publicKey)
        try await wait("other key connected") { await linkW.count(HostProtocol.Method.listAgentSessions) > 0 }
        try require(session.host?.client === clientF, "A pairing with another key took the task over")
        try require(await linkW.count(HostProtocol.Method.attach) == 0, "A pairing with another key attached the task")
        let (current, clientG, _) = await pair(process, key: hostKey)
        try await wait("right key takes over") { session.host?.client === clientG }
        print("PASS: only a pairing that pins the same key takes the task over")
        var clients = [clientA, clientB, clientC, clientD, clientE, clientF, clientW, clientG, clientZ]

        #if !BEFORE
        // A pairing the host ended hands nothing over by itself.
        current.pairingEnded(.revoked)
        let (_, clientI, linkI) = await pair(process, key: hostKey)
        clients.append(clientI)
        try await wait("pairing after it ended") { await linkI.count(HostProtocol.Method.listAgentSessions) > 0 }
        try require(session.host?.client === clientG, "An ended pairing's task moved by itself")
        try require(await linkI.count(HostProtocol.Method.attach) == 0, "An ended pairing's task was attached")
        print("PASS: an ended pairing's tasks don't move by themselves")
        try require(app.sessions.sessions(on: clientZ).map(\.key) == [otherKey], "Tasks crossed hosts")
        #endif

        try require(otherSession.host?.client === clientZ, "Another host's task changed client")
        try await wait("plugins") { plugins.count("turnEnded") == 1 }
        try require(plugins.count("permissionRequested") == 2, "Approvals were announced twice")
        try require(plugins.count("promptSent") == 2, "Messages were announced twice")
        try require(plugins.count("turnEnded") == 1, "Turn ends were announced twice")
        print("PASS: no duplicate notifications, and other hosts keep their clients")
        for client in clients { await client.stop() }
        _ = current
    }
}
