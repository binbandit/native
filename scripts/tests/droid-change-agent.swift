import ACP
import Experiments
import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import Native
@testable import NativeLink

// Change Agent for a task on a paired host, through the app's own model actions: one fake host
// process running two fake agents, reached through fake pairings, and a recording host standing in
// for this Mac's agents. The replacement must start on the task's host in its folder with the
// reviewed handoff and model, survive a new pairing, a dropped answer and a relaunch, and never
// run, clone, make a worktree or list anything on this Mac.

private struct ChangeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func chunk(_ text: String) -> HostEvent.Payload {
    .update(
        .object([
            "sessionUpdate": .string("agent_message_chunk"),
            "content": .object(["type": .string("text"), "text": .string(text)]),
        ]))
}

/// The host process, shared by every pairing's link to it: its agents, its sessions' event logs,
/// and what it was asked.
private actor ChangeHost {
    enum Reply: Sendable { case answer, dropConnection, reject, withhold }

    let hostID = HostID()
    let epoch = UUID()
    private(set) var agents: [HostAgent]
    private(set) var summaries: [HostSessionSummary]
    private var logs: [HostSessionID: [HostEvent]] = [:]
    private var followers: [HostSessionID: [ChangeLink]] = [:]
    private var links: [ChangeLink] = []
    /// Every request's method, and each command it was asked to run, in arrival order.
    private(set) var calls: [String] = []
    /// Model changes and prompts as "config <session> <value>" and "prompt <session>".
    private(set) var order: [String] = []
    private(set) var started: [NewSessionParams] = []
    private(set) var accepted: [PromptParams] = []
    private(set) var closed: [HostSessionID] = []
    private var failsStart = false
    private var failsNew = false
    private var reply = Reply.answer

    init(folder: String, source: SessionID) {
        agents = [Self.agent("fixture", "Fixture", .ready), Self.agent("droid", "Droid", .stopped)]
        let id = HostSessionID()
        summaries = [
            HostSessionSummary(
                id: id, agentID: "fixture", agentName: "Fixture", agentSessionID: source, cwd: folder, phase: .idle,
                lastStopReason: "end_turn")
        ]
        let history: [HostEvent.Payload] = [
            .reset(loading: false), .prompt(PromptEcho(text: "Fix the login form")), chunk("Fixed the form."),
            .turnEnded(stopReason: "end_turn"),
        ]
        logs[id] = history.enumerated().map { HostEvent(seq: $0.offset + 1, payload: $0.element) }
    }

    static func agent(_ id: String, _ name: String, _ state: HostAgentState, problem: String? = nil) -> HostAgent {
        let running: JSONValue = .object([
            "protocolVersion": .number(1),
            "agentCapabilities": .object([
                "loadSession": .bool(true), "sessionCapabilities": .object(["close": .object([:])]),
            ]),
        ])
        return HostAgent(
            id: id, name: name, state: state, problem: problem, initialize: state == .ready ? running : nil)
    }

    static func models(_ current: String) -> HostEvent.Payload {
        let model: JSONValue = .object([
            "id": .string("model"), "name": .string("Model"), "category": .string("model"),
            "type": .string("select"), "currentValue": .string(current),
            "options": .array(["small", "large"].map { .object(["value": .string($0), "name": .string($0)]) }),
        ])
        return .update(.object(["sessionUpdate": .string("config_option_update"), "configOptions": .array([model])]))
    }

    func configure(failsStart: Bool = false, failsNew: Bool = false, reply: Reply = .answer) {
        self.failsStart = failsStart
        self.failsNew = failsNew
        self.reply = reply
    }

    func setAgent(_ id: String, _ state: HostAgentState) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index] = Self.agent(id, agents[index].name, state)
    }

    func join(_ link: ChangeLink) {
        if !links.contains(where: { $0 === link }) { links.append(link) }
    }

    func record(_ call: String) { calls.append(call) }

    func start(_ agentID: String) -> HostAgent? {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return nil }
        let name = agents[index].name
        agents[index] =
            failsStart
            ? Self.agent(agentID, name, .failed, problem: "It exited at launch.") : Self.agent(agentID, name, .ready)
        return agents[index]
    }

    func newSession(_ params: NewSessionParams, for link: ChangeLink) async -> HostSessionSummary? {
        guard !failsNew, let agent = agents.first(where: { $0.id == params.agentID && $0.state == .ready }) else {
            return nil
        }
        started.append(params)
        let id = params.sessionID ?? HostSessionID()
        let summary = HostSessionSummary(
            id: id, agentID: agent.id, agentName: agent.name,
            agentSessionID: SessionID("\(agent.id)-\(started.count)-\(UUID().uuidString.prefix(8))"), cwd: params.cwd,
            phase: .idle)
        summaries.append(summary)
        followers[id] = [link]
        await log(Self.models("small"), in: id)
        await announce(summary)
        return summary
    }

    func open(_ params: OpenSessionParams, for link: ChangeLink) async -> HostSessionSummary? {
        guard let summary = summaries.first(where: { $0.agentSessionID == params.agentSessionID }) else { return nil }
        for event in attach(link, to: summary.id, after: nil, epoch: nil) { await link.send(event, of: summary.id) }
        return summary
    }

    /// Subscribes `link` and returns what it hasn't seen, in one step, as the real host does.
    func attach(_ link: ChangeLink, to id: HostSessionID, after seq: Int?, epoch: UUID?) -> [HostEvent] {
        followers[id, default: []].removeAll { $0 === link }
        followers[id, default: []].append(link)
        let all = logs[id] ?? []
        guard epoch == self.epoch, let seq else { return all }
        return all.filter { $0.seq > seq }
    }

    func summary(_ id: HostSessionID) -> HostSessionSummary? { summaries.first { $0.id == id } }

    func setConfig(_ params: SetConfigOptionParams) async {
        order.append("config \(params.sessionID) \(params.value)")
        await log(Self.models(params.value), in: params.sessionID)
    }

    /// Delivers each request id once, as the real host does, and says how to answer this one.
    func prompt(_ params: PromptParams) async -> Reply {
        if accepted.contains(where: { $0.requestID == params.requestID }) { return .answer }
        order.append("prompt \(params.sessionID)")
        let reply = self.reply
        if reply == .dropConnection { self.reply = .answer }
        guard reply != .reject else { return .reject }
        accepted.append(params)
        await log(.prompt(PromptEcho(text: params.text, requestID: params.requestID)), in: params.sessionID)
        guard reply != .withhold else { return .withhold }
        await log(chunk("Picking up from the handoff."), in: params.sessionID)
        await log(.turnEnded(stopReason: "end_turn"), in: params.sessionID)
        await update(params.sessionID) { $0.lastStopReason = "end_turn" }
        return reply
    }

    func update(_ id: HostSessionID, _ change: @Sendable (inout HostSessionSummary) -> Void) async {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else { return }
        change(&summaries[index])
        await announce(summaries[index])
    }

    func close(_ id: HostSessionID) async {
        closed.append(id)
        summaries.removeAll { $0.id == id }
        for link in links { await link.closed(id) }
    }

    func log(_ payload: HostEvent.Payload, in id: HostSessionID) async {
        let event = HostEvent(seq: (logs[id]?.last?.seq ?? 0) + 1, payload: payload)
        logs[id, default: []].append(event)
        for link in followers[id] ?? [] { await link.send(event, of: id) }
    }

    private func announce(_ summary: HostSessionSummary) async {
        for link in links { await link.changed(summary) }
    }
}

/// One pairing's connection to the host process.
private actor ChangeLink: HostTransport {
    nonisolated var displayName: String { "Build box" }
    let host: ChangeHost
    private var peer: JSONRPCPeer?
    private var isOffline = false

    init(_ host: ChangeHost) { self.host = host }

    /// Drops the connection and refuses new ones until `reconnect()`.
    func goOffline() {
        isOffline = true
        peer?.close()
    }

    func reconnect() { isOffline = false }

    func connect() async throws -> any ByteStream {
        guard !isOffline else { throw ChangeFailure("The fixture host is offline") }
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "droid-host"), label: "droid-host") {
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
        await host.join(self)
        return ByteChannel.socket(clientEnd, label: "droid-client")
    }

    func send(_ event: HostEvent, of id: HostSessionID) {
        try? peer?.notify(HostProtocol.Method.sessionEvent, SessionEventNotification(sessionID: id, event: event))
    }

    func changed(_ summary: HostSessionSummary) {
        try? peer?.notify(HostProtocol.Method.sessionChanged, SessionChangedNotification(summary: summary))
    }

    func closed(_ id: HostSessionID) {
        try? peer?.notify(HostProtocol.Method.sessionClosed, SessionParams(sessionID: id))
    }

    private func receive(_ message: JSONRPCPeer.Message) async throws {
        guard let id = message.id, let peer else { return }
        await host.record(message.method)
        let refused = RPCError(code: -32603, message: "The fixture refused \(message.method)")
        switch message.method {
        case HostProtocol.Method.initialize:
            try peer.respond(
                to: id,
                with: HostInfo(
                    protocolVersion: HostProtocol.version, hostID: host.hostID, machineName: displayName,
                    hostInfo: PeerInfo(name: "Fixture", version: "1", build: "1"), epoch: host.epoch,
                    processID: 1, startedAt: .now, channel: "tests"))
        case HostProtocol.Method.listAgents:
            try peer.respond(to: id, with: await host.agents)
        case HostProtocol.Method.startAgent:
            let params = try message.params(as: AgentParams.self)
            guard let agent = await host.start(params.agentID) else { return try peer.respond(to: id, error: refused) }
            try peer.respond(to: id, with: agent)
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: await host.summaries)
        case HostProtocol.Method.listAgentSessions:
            try peer.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
        case HostProtocol.Method.newSession:
            let params = try message.params(as: NewSessionParams.self)
            guard let summary = await host.newSession(params, for: self) else {
                return try peer.respond(to: id, error: refused)
            }
            try peer.respond(to: id, with: summary)
        case HostProtocol.Method.openSession:
            let params = try message.params(as: OpenSessionParams.self)
            guard let summary = await host.open(params, for: self) else {
                return try peer.respond(to: id, error: refused)
            }
            try peer.respond(to: id, with: summary)
        case HostProtocol.Method.attach:
            let params = try message.params(as: AttachParams.self)
            let replay = await host.attach(self, to: params.sessionID, after: params.afterSeq, epoch: params.epoch)
            for event in replay { send(event, of: params.sessionID) }
            guard let summary = await host.summary(params.sessionID) else {
                return try peer.respond(to: id, error: refused)
            }
            try peer.respond(to: id, with: AttachResult(summary: summary))
        case HostProtocol.Method.setConfigOption:
            await host.setConfig(try message.params(as: SetConfigOptionParams.self))
            try peer.respond(to: id, with: EmptyMessage())
        case HostProtocol.Method.prompt:
            switch await host.prompt(try message.params(as: PromptParams.self)) {
            case .answer: try peer.respond(to: id, with: PromptResult(delivery: .prompted))
            case .dropConnection: peer.close()
            case .reject: try peer.respond(to: id, error: RPCError(code: -32603, message: "The agent went away"))
            case .withhold: break
            }
        case HostProtocol.Method.closeSession:
            await host.close(try message.params(as: CloseSessionParams.self).sessionID)
            try peer.respond(to: id, with: EmptyMessage())
        case HostProtocol.Method.execRun:
            // Recorded so a clone or a new worktree would show; this host runs nothing.
            if let run = try? message.params(as: ExecRunParams.self) {
                await host.record("exec \(([run.executable] + run.arguments).joined(separator: " "))")
            }
            try peer.respond(to: id, error: refused)
        case HostProtocol.Method.configureTitles, HostProtocol.Method.detach, HostProtocol.Method.cancel:
            try peer.respond(to: id, with: EmptyMessage())
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
}

/// This Mac's own host: it has agents of its own, records what it's asked and never runs a task.
private actor ThisMacHost: HostTransport {
    nonisolated var displayName: String { "This Mac fixture" }
    private let hostID = HostID()
    private let epoch = UUID()
    private var peer: JSONRPCPeer?
    private(set) var calls: [String] = []

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "mac-host"), label: "mac-host") {
            [weak self] event in
            if case .request(let message) = event {
                Task {
                    do { try await self?.receive(message) } catch {
                        print("FAIL: this Mac's host request \(message.method): \(error)")
                        exit(1)
                    }
                }
            }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "mac-client")
    }

    private func receive(_ message: JSONRPCPeer.Message) throws {
        guard let id = message.id, let peer else { return }
        calls.append(message.method)
        let agents = [
            ChangeHost.agent("fixture", "Fixture", .ready), ChangeHost.agent("local-only", "Local Only", .ready),
        ]
        switch message.method {
        case HostProtocol.Method.initialize:
            try peer.respond(
                to: id,
                with: HostInfo(
                    protocolVersion: HostProtocol.version, hostID: hostID, machineName: displayName,
                    hostInfo: PeerInfo(name: "Fixture", version: "1", build: "1"), epoch: epoch, processID: 1,
                    startedAt: .now, channel: "tests"))
        case HostProtocol.Method.listAgents:
            try peer.respond(to: id, with: agents)
        case HostProtocol.Method.startAgent:
            let params = try message.params(as: AgentParams.self)
            guard let agent = agents.first(where: { $0.id == params.agentID }) else {
                return try peer.respond(to: id, error: .methodNotFound(message.method))
            }
            try peer.respond(to: id, with: agent)
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: [HostSessionSummary]())
        case HostProtocol.Method.listAgentSessions:
            try peer.respond(to: id, with: JSONValue.object(["sessions": .array([])]))
        case HostProtocol.Method.syncAgents, HostProtocol.Method.configureTitles:
            try peer.respond(to: id, with: EmptyMessage())
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
}

/// The paired host's task workspaces: Change Agent must never make, move or remove one.
@MainActor
private final class WorkspaceTripwire: TaskWorkspaceProvider {
    private(set) var calls: [String] = []

    func workspaceOptions(in project: Project, current: URL) async throws -> [TaskWorkspaceOption] { [] }
    func workspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> URL {
        calls.append("workspace")
        return project.url
    }
    func prepareWorkspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> TaskWorkspacePreparation
    {
        calls.append("prepare")
        return .init(folder: project.url, createdForTask: false)
    }
    func removeUnusedWorkspace(at folder: URL, in project: Project) async throws -> Bool {
        calls.append("removeUnused")
        return false
    }
    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL {
        calls.append("newTask")
        return project.url
    }
    func newTaskWorkspaceLabel(in project: Project) -> String { "Fixture" }
    func archiveWorkspace(at folder: URL, in project: Project) async throws -> String? {
        calls.append("archive")
        return nil
    }
    func restoreWorkspace(at folder: URL, in project: Project, task: ArchivedTaskDetails?) async throws -> Bool {
        calls.append("restore")
        return false
    }
    func archivedWorkspaceFolders(of project: Project) async -> [URL] { [] }
    func removedWorkspaces(
        among tasks: [(folder: URL, title: String)], in project: Project
    ) async -> [URL: RemovedWorkspace.Fate] { [:] }
    func restoreRemovedWorkspace(at folder: URL, branch: String, in project: Project) async throws {
        calls.append("restoreRemoved")
    }
    func deleteWorkspace(at folder: URL, in project: Project) async throws { calls.append("delete") }
    func deleteWorkspaces(of project: Project) async throws { calls.append("deleteAll") }
    func taskDidGetTitle(_ title: String, request: String?, workspace: URL, in project: Project) async {}
    func taskFolders(of project: Project) async -> [URL] { [] }
}

@main
@MainActor
private struct DroidChangeAgentRegression {
    static func main() async {
        // Titles and remembered settings live in the standard defaults: start and end with none.
        let domain = ProcessInfo.processInfo.processName
        UserDefaults.standard.removePersistentDomain(forName: domain)
        do { try await run() } catch {
            print("FAIL: \(error)")
            UserDefaults.standard.removePersistentDomain(forName: domain)
            exit(1)
        }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ChangeFailure(message) }
    }

    static func wait(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw ChangeFailure("Timed out: \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func says(_ session: SessionModel, _ role: TranscriptMessage.Role, _ text: String) -> Bool {
        session.state.items.contains { item in
            if case .message(let message) = item { message.role == role && message.text == text } else { false }
        }
    }

    static func run() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "droid-change-agent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let defaults = PreviewUserDefaults()
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        let peerInfo = PeerInfo(name: "Fixture", version: "1", build: "1")
        let droid = AgentDefinition.ID(rawValue: "droid")
        let run = UUID().uuidString.prefix(8)
        let folder = "/droid/worktrees/repo/task"
        let sourceKey = SessionKey(agent: .init(rawValue: "fixture"), id: SessionID("source-\(run)"))
        let process = ChangeHost(folder: folder, source: sourceKey.id)
        let hostKey = LinkIdentity().publicKey
        let workspaces = WorkspaceTripwire()

        /// The app as a launch makes it, with the paired-host wiring of `AppModel.startRemoteHosts`
        /// but no network, its agents on a recording host of this Mac's own.
        func launch(_ name: String) async throws -> (AppModel, ThisMacHost, NativeHostClient) {
            let manifest = PluginManifest(
                id: "fixture", name: "Fixture",
                agents: [
                    AgentManifest(id: "fixture", name: "Fixture", command: "/usr/bin/true"),
                    AgentManifest(id: "local-only", name: "Local Only", command: "/usr/bin/true"),
                ])
            let app = AppModel(
                plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
                titles: SessionTitles(), defaults: defaults, catalogURL: scratch.appending(path: "catalog.json"),
                experiments: experiments,
                hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appending(path: name))))
            app.hosts.definition = { [weak app] agent in
                app?.plugins.agent(AgentDefinition.ID(rawValue: agent.id)) ?? RemoteHost.definition(from: agent)
            }
            app.hosts.onEvent = { [weak app] _, event in
                app?.sessions.handle(event)
                switch event {
                case .sessionChanged, .sessionClosed: app?.indexRemoteSessions()
                default: break
                }
            }
            app.hosts.onRefreshed = { [weak app] host in Task { await app?.hostConnected(host) } }
            app.launcher.isRemote = { [hosts = app.hosts] client in hosts.all.contains { $0.client === client } }
            let here = ThisMacHost()
            let client = NativeHostClient(transport: here, clientInfo: peerInfo)
            await client.start()
            _ = try await client.connected()
            app.connectHost(client: client)
            await app.followHost()
            _ = await app.checkForAgents()
            return (app, here, client)
        }

        /// Pairs `app` with the host process through a new link, as pairing it (again) does.
        func pair(_ app: AppModel, key: LinkPublicKey) async throws -> (RemoteHost, NativeHostClient, ChangeLink) {
            let link = ChangeLink(process)
            let client = NativeHostClient(transport: link, clientInfo: peerInfo)
            let remote = app.hosts.add(
                PairedHost(
                    result: LinkPairingResult(
                        hostID: process.hostID, hostKey: key, hostName: "Build box", deviceID: UUID(),
                        grants: LinkGrants(), addresses: []), identity: LinkIdentity()))
            remote.worktreesFolder = "/droid/worktrees"
            remote.taskWorkspaces = workspaces
            if let project = app.projects.all.first { app.setCheckout("/droid/repo", of: project.id, on: remote.id) }
            remote.start(using: client)
            try await wait("the host connects") {
                remote.isOnline && remote.runtime(droid) != nil && !remote.sessions.isEmpty
            }
            app.indexRemoteSessions()
            return (remote, client, link)
        }

        let (app, here, hereClient) = try await launch("hosts")
        let project = app.projects.add(URL(filePath: "/droid/repo"))
        let first = try await pair(app, key: hostKey)
        var (remote, client) = (first.0, first.1)
        let link = first.2
        let hereStarts = await here.calls.filter { $0 == HostProtocol.Method.startAgent }.count

        if !app.offersRemoteHosts {
            // Paired hosts off (the default): a task on a host that isn't offered changes to nothing.
            guard let summary = remote.sessions.first, let agent = app.plugins.agent(sourceKey.agent) else {
                throw ChangeFailure("No host task")
            }
            let source = SessionModel(
                agent: agent, id: sourceKey.id, summary: summary, client: client, services: app.sessions.services,
                promptCapabilities: PromptCapabilities(), origin: .user, parent: nil)
            app.sessions.register(source)
            experiments.set(true, for: .changeAgent)
            try require(
                app.changeAgentChoices(for: source).isEmpty,
                "An agent was offered for a host's task with paired hosts off")
            try require(app.changeAgentBlock(for: source) != nil, "A host's task could change with paired hosts off")
            _ = try? await app.prepareAgentChange(source, to: AgentDefinition.ID(rawValue: "local-only"))
            try require(await process.started.isEmpty, "A replacement started with paired hosts off")
            try require(
                !(await here.calls).contains(HostProtocol.Method.newSession), "A host's task started on this Mac")
            print("PASS: with paired hosts off, a host's task offers no agents and starts nothing")
            await client.stop()
            await hereClient.stop()
            return
        }

        try require(await app.loadRemoteSession(sourceKey), "The host's task didn't open")
        guard let source = app.sessions.session(sourceKey), let sourceLink = source.host else {
            throw ChangeFailure("No model for the host's task")
        }
        try await wait("the host's task loads") { source.hasStarted && source.phase == .idle }
        app.titles.rename(source.titleKey, to: "Fix the login form")
        app.ordering.pin(source.key)
        source.draft = "Keep this draft"
        let unfinishedComment = DiffCommentsPreviewFixtures.quotes(task: source.clientID)[0]
        source.beginDiffComment(unfinishedComment)
        let attachment = PromptAttachment(
            url: scratch.appending(path: "notes.txt"), content: .text("Fixture"), byteCount: 7)
        source.attachments = [attachment]
        app.selection = source.key

        func intact(_ what: String) throws {
            try require(
                app.sessions.session(source.key) === source && app.selection == source.key, "\(what): task gone")
            try require(source.draft == "Keep this draft" && source.attachments == [attachment], "\(what): lost draft")
            try require(source.diffCommentEditors == [unfinishedComment], "\(what): lost unfinished comment")
            try require(!source.isEarlierConversation && app.ordering.isPinned(source.key), "\(what): set aside")
            try require(source.host?.client != nil && source.cwd.folderPath == folder, "\(what): moved the task")
        }

        experiments.set(false, for: .changeAgent)
        try require(!experiments.value(of: .changeAgent), "Change Agent ignored its opt-out")
        try require(
            app.changeAgentBlock(for: source) == "Enable Change Agent in Settings > Labs first.",
            "Change Agent isn't behind its Labs switch")
        experiments.set(true, for: .changeAgent)
        try require(
            app.changeAgentBlock(for: source) == nil,
            "A paired host's task can't change agents: \(app.changeAgentBlock(for: source) ?? "")")
        try require(
            app.changeAgentChoices(for: source).map(\.agent.id) == [droid] && app.runtime(droid) == nil,
            "Choices aren't the task's host's agents: \(app.changeAgentChoices(for: source).map(\.agent.id))")
        print("PASS: a paired host's task offers only that host's other agents, behind the Labs switch")

        // Every guard the change has on this Mac holds for a host's task, and starts nothing there.
        func refuses(_ what: String, saying fragment: String) async throws {
            let reason = app.changeAgentBlock(for: source)
            try require(reason?.contains(fragment) == true, "\(what) didn't block the change: \(reason ?? "nil")")
            let starts = await process.started.count
            if (try? await app.prepareAgentChange(source, to: droid)) != nil {
                throw ChangeFailure("\(what) let a replacement start")
            }
            try require(await process.started.count == starts, "\(what) started a session on the host")
            try intact(what)
        }
        await process.update(sourceLink.id) { $0.phase = .prompting }
        try await wait("a running turn") { source.phase == .prompting }
        try await refuses("A running turn", saying: "Finish or stop")
        await process.update(sourceLink.id) {
            $0.phase = .idle; $0.retryAt = .now + 60
        }
        try await wait("a scheduled retry") { source.isRetryScheduled && source.phase == .idle }
        try await refuses("A scheduled retry", saying: "Finish or stop")
        await process.update(sourceLink.id) { $0.retryAt = nil }
        try await wait("no retry") { !source.isRetryScheduled }
        source.heldPrompts = [HeldPrompt(text: "Later", attachments: [], behavior: .queue, isEchoed: true)]
        try await refuses("A queued message", saying: "queued messages")
        source.heldPrompts = []
        await process.log(
            .permissionRequested(
                toolCallID: "call-1",
                request: .object([
                    "sessionId": .string(sourceKey.id.rawValue),
                    "toolCall": .object(["toolCallId": .string("call-1"), "title": .string("Write notes.txt")]),
                    "options": .array([
                        .object(["optionId": .string("allow"), "name": .string("Allow"), "kind": .string("allow_once")])
                    ]),
                ])), in: sourceLink.id)
        try await wait("an approval") { source.needsApproval }
        try await refuses("A pending approval", saying: "pending requests")
        await process.log(.permissionResolved(toolCallID: "call-1", optionID: "allow"), in: sourceLink.id)
        try await wait("the approval answered") { !source.needsApproval }
        app.agentChangeGoalBlock = { _ in "Pause the task's goal before changing agents." }
        try await refuses("An active goal", saying: "Pause the task's goal")
        app.agentChangeGoalBlock = { _ in nil }
        let child = SessionModel(
            agent: source.agent, id: SessionID("child-\(run)"),
            summary: HostSessionSummary(
                id: HostSessionID(), agentID: "fixture", agentName: "Fixture",
                agentSessionID: SessionID("child-\(run)"),
                cwd: folder, parentID: sourceLink.id, origin: .task, phase: .prompting),
            client: client, services: app.sessions.services, promptCapabilities: PromptCapabilities(), origin: .task,
            parent: source)
        try await refuses("A working subagent", saying: "subagents")
        child.phase = .idle
        app.removedWorkspaces[source.key] = RemovedWorkspace(branch: "fix-login", detail: "Fixture")
        try await refuses("A removed worktree", saying: "available worktree")
        app.removedWorkspaces[source.key] = nil
        app.coordinators = [
            HostCoordinator(
                task: HostTaskIdentity(agentID: "fixture", agentSessionID: SessionID("coordinator-\(run)")),
                projectPath: "/droid/repo", assignments: [source.key.coordinatorIdentity])
        ]
        try await refuses("A coordinator's assignment", saying: "coordinator")
        app.coordinators = []
        try require(app.changeAgentBlock(for: source) == nil, "The guards didn't clear")
        print("PASS: running, retrying, queued, approval, goal, subagent, worktree and coordinator guards hold")

        // No eligible agent, an agent that fails to start, a session that fails to start and an
        // offline host each leave the task as it was.
        await process.setAgent("droid", .notInstalled)
        await remote.refresh()
        try require(app.changeAgentChoices(for: source).isEmpty, "An agent that can't run was offered")
        app.requestAgentChange(source)
        guard let none = app.changingAgent else { throw ChangeFailure("Change Agent didn't open") }
        try require(none.agentID == nil, "The review picked an agent that can't run")
        await none.prepare()
        try require(none.candidate == nil, "No eligible agent made a candidate")
        try require(await process.started.isEmpty, "No eligible agent started a session")
        none.cancel()
        try intact("No eligible agent")
        await process.setAgent("droid", .stopped)
        await remote.refresh()
        func review() async throws -> ChangeAgentModel {
            app.requestAgentChange(source)
            guard let change = app.changingAgent else { throw ChangeFailure("Change Agent didn't open") }
            await change.loadContext()
            try require(change.agentID == droid && !change.handoff.isEmpty, "The review isn't ready")
            return change
        }
        await process.configure(failsStart: true)
        var change = try await review()
        await change.prepare()
        try require(
            change.candidate == nil && change.error?.contains("Couldn't start Droid on Build box") == true,
            "An agent that failed to start wasn't explained: \(change.error ?? "nil")")
        try require(await process.started.isEmpty, "A failed agent started a session")
        change.cancel()
        try intact("An agent that failed to start")
        await process.configure(failsNew: true)
        await process.setAgent("droid", .stopped)
        await remote.refresh()
        change = try await review()
        await change.prepare()
        try require(change.candidate == nil && change.error != nil, "A session that failed to start wasn't explained")
        change.cancel()
        try intact("A session that failed to start")
        await process.configure()
        await link.goOffline()
        try await wait("the host goes offline") { !remote.isOnline }
        try await refuses("An offline host", saying: "Reconnect Build box")
        await link.reconnect()
        try await wait("the host is back") { remote.isOnline && app.changeAgentBlock(for: source) == nil }
        print("PASS: no eligible agent, failed starts and an offline host leave the task as it was")

        // An unsent candidate runs on the task's host, hidden, and Cancel closes it there.
        change = try await review()
        await change.prepare()
        guard let cancelled = change.candidate, let cancelledLink = cancelled.host else {
            throw ChangeFailure("No candidate: \(change.error ?? "")")
        }
        let start = await process.started.last
        try require(
            cancelledLink.client === client && start?.agentID == "droid" && start?.cwd == folder
                && cancelled.cwd == source.cwd, "The candidate didn't start on the task's host in its folder")
        try require(
            change.modelChoices.map(\.value) == ["small", "large"] && change.modelValue == "small",
            "The review doesn't offer the candidate's live models")
        try require(
            app.deletedSessions.contains(cancelled.key) && !app.sessionList.contains { $0.id == cancelled.key },
            "The unsent candidate shows in the sidebar")
        try require(
            !app.unsentSessions.contains(cancelled.key) && app.catalog.sessions(in: project.id, of: droid).isEmpty,
            "The candidate went into this Mac's catalog or drafts")
        change.cancel()
        try await wait("Cancel closes the candidate on its host") { await process.closed.contains(cancelledLink.id) }
        try require(app.sessions.session(cancelled.key) == nil && app.changingAgent == nil, "Cancel kept the candidate")
        try intact("Cancel")
        print("PASS: the unsent candidate starts hidden on the task's host and Cancel closes it there")

        // Another key under the host's id takes nothing over: the review can't send, the task stays.
        change = try await review()
        await change.prepare()
        guard let stranded = change.candidate else { throw ChangeFailure("No candidate: \(change.error ?? "")") }
        let (intruder, intruderClient, _) = try await pair(app, key: LinkIdentity().publicKey)
        try require(source.host?.client === client, "A pairing with another key took the task over")
        try require(
            app.changeAgentBlock(for: source)?.contains("Reconnect the task's host") == true
                && app.changeAgentChoices(for: source).isEmpty, "A replaced pairing still offers a change")
        await change.send()
        try require(change.error != nil, "A handoff through another key wasn't refused")
        try require(await process.accepted.isEmpty, "A handoff went out through another key")
        change.cancel()
        try require(app.deletedSessions.contains(stranded.key), "The stranded candidate isn't hidden")
        try intact("Pairing with another key")
        (remote, client, _) = try await pair(app, key: hostKey)
        try await wait("the right key takes the task back") {
            source.host?.client === client && app.changeAgentBlock(for: source) == nil
        }
        _ = intruder
        print("PASS: another key strands nothing: the review can't send and the task stays")

        // The accepted handoff: reviewed, pairing again meanwhile, its first answer dropped.
        let uncertainPacket = unfinishedComment.prompt
        source.unresolvedCommentPacket = uncertainPacket
        change = try await review()
        await change.prepare()
        guard let target = change.candidate else { throw ChangeFailure("No candidate: \(change.error ?? "")") }
        let reviewed = "Carry on from here on the build box.\n\n" + change.handoff
        change.handoff = reviewed
        change.modelValue = "large"
        let previous = client
        (remote, client, _) = try await pair(app, key: hostKey)
        try await wait("both conversations move to the new pairing") {
            source.host?.client === client && target.host?.client === client
                && app.changeAgentBlock(for: source) == nil
        }
        try require(previous !== client, "Pairing again kept the old client")
        await process.configure(reply: .dropConnection)
        await change.send()
        try require(change.error == nil && app.changingAgent == nil, "The handoff failed: \(change.error ?? "")")
        guard let targetLink = target.host else { throw ChangeFailure("The new task left its host") }
        let accepted = await process.accepted
        let sent = reviewed.trimmingCharacters(in: .whitespacesAndNewlines)
        try require(
            accepted.count == 1 && accepted.first?.sessionID == targetLink.id && accepted.first?.text == sent,
            "The host didn't take the reviewed handoff exactly once")
        let order = await process.order
        guard let configured = order.firstIndex(of: "config \(targetLink.id) large"),
            let prompted = order.firstIndex(of: "prompt \(targetLink.id)"), configured < prompted
        else { throw ChangeFailure("The model wasn't set before the first prompt: \(order)") }
        try require(
            app.selection == target.key && targetLink.client === client
                && app.device(of: target.key) == .remote(remote.id)
                && app.taskActionOwner(for: target.key) == .remote(remote.id), "The new task isn't the host's")
        try require(target.cwd == source.cwd && target.displayTitle == "Fix the login form", "Lost the folder or title")
        try require(app.ordering.isPinned(target.key) && !app.ordering.isPinned(source.key), "Lost the pin")
        try require(
            target.draft == "Keep this draft" && target.attachments == [attachment] && source.draft.isEmpty
                && source.attachments.isEmpty, "The draft didn't move to the new task")
        try require(
            target.diffCommentEditors == [unfinishedComment] && source.diffCommentEditors.isEmpty
                && target.unresolvedCommentPacket == uncertainPacket && source.unresolvedCommentPacket == nil,
            "Unfinished comments and uncertain delivery must move only after the handoff commits")
        try require(
            app.earlierConversations.conversation(before: target.key) == source.key && source.isEarlierConversation,
            "The earlier conversation isn't linked")
        try require(
            app.sessionList.filter { $0.id == target.key }.count == 1
                && !app.sessionList.contains { $0.id == source.key },
            "The sidebar doesn't show the task once, as its new conversation")
        try require(
            app.catalog.remote[target.key] != nil && app.catalog.sessions(in: project.id, of: droid).isEmpty
                && !app.unsentSessions.contains(target.key) && !app.deletedSessions.contains(target.key),
            "The new task isn't listed by its host alone")
        try require(
            ComposerSettings(target.configOptions).model?.value == "large", "The chosen model didn't stick")
        print("PASS: the reviewed handoff lands once on the host, through a new pairing and a dropped answer")

        // Nothing ran here, and nothing on the host was cloned, made or moved.
        let starts = await process.started
        try require(
            starts.count == 3 && starts.allSatisfy { $0.agentID == "droid" && $0.cwd == folder },
            "A replacement started elsewhere: \(starts.map(\.cwd))")
        let hostCalls = await process.calls
        try require(
            !hostCalls.contains { $0.contains("clone") || $0.contains("worktree") }
                && !hostCalls.contains(HostProtocol.Method.addProject), "The host was asked to clone or make a worktree"
        )
        try require(workspaces.calls.isEmpty, "A task workspace was touched: \(workspaces.calls)")
        let hereCalls = await here.calls
        for method in [
            HostProtocol.Method.newSession, HostProtocol.Method.openSession, HostProtocol.Method.prompt,
            HostProtocol.Method.closeSession, HostProtocol.Method.setConfigOption,
        ] {
            try require(!hereCalls.contains(method), "This Mac's host was asked for \(method)")
        }
        try require(
            hereCalls.filter { $0 == HostProtocol.Method.startAgent }.count == hereStarts,
            "An agent started on this Mac")
        print("PASS: no agent ran on this Mac, and no checkout or worktree was made")

        // A rejected handoff is never sent twice, and its candidate stays openable.
        change = try await reviewTarget(app, target)
        await change.prepare()
        guard let unconfirmed = change.candidate, let unconfirmedLink = unconfirmed.host else {
            throw ChangeFailure("No candidate: \(change.error ?? "")")
        }
        await process.configure(reply: .reject)
        await change.send()
        await change.send()
        try require(change.error?.contains("Couldn't confirm") == true, "A rejected handoff wasn't explained")
        try require(
            (await process.order).filter { $0 == "prompt \(unconfirmedLink.id)" }.count == 1,
            "A rejected handoff was sent again")
        change.cancel()
        try require(!(await process.closed.contains(unconfirmedLink.id)), "A published candidate was closed")
        try require(
            app.sessions.session(unconfirmed.key) === unconfirmed
                && app.sessionList.contains { $0.id == unconfirmed.key },
            "A published candidate was hidden")
        try require(
            app.earlierConversations.conversation(after: target.key) == nil && !target.isEarlierConversation,
            "An unconfirmed handoff replaced the task")

        // A handoff whose answer never comes, then a quit: the work that reached the agent stays listed.
        await process.configure(reply: .withhold)
        change = try await reviewTarget(app, target)
        await change.prepare()
        guard let unanswered = change.candidate else { throw ChangeFailure("No candidate: \(change.error ?? "")") }
        let waiting = change
        Task { await waiting.send() }
        try await wait("the host takes the handoff") { unanswered.hasStarted }
        change.cancel()
        try require(app.changingAgent === change && change.candidate === unanswered, "Cancel dropped a sending handoff")
        try require(
            !DeletedSessions(defaults: defaults).contains(unanswered.key), "A sent handoff would vanish on quit")
        await process.configure()
        print("PASS: an unconfirmed handoff never goes twice, and one in flight survives a quit")

        // A relaunch reopens both conversations from the host, linked, pinned and titled.
        remote.stop()
        await client.stop()
        await intruderClient.stop()
        await hereClient.stop()
        let opens = await process.calls.filter { $0 == HostProtocol.Method.openSession }.count
        let (relaunched, hereAgain, hereAgainClient) = try await launch("hosts-relaunched")
        let (again, againClient, _) = try await pair(relaunched, key: hostKey)
        let listed = relaunched.sessionList.map(\.id)
        try require(listed.contains(target.key) && !listed.contains(source.key), "The relaunched sidebar is wrong")
        try require(
            listed.contains(unconfirmed.key) && listed.contains(unanswered.key),
            "A handoff that reached the host was lost on relaunch")
        try require(
            !listed.contains(cancelled.key) && !listed.contains(stranded.key), "A cancelled candidate came back")
        try require(
            relaunched.earlierConversations.conversation(before: target.key) == source.key
                && relaunched.ordering.isPinned(target.key)
                && relaunched.titleOfSession(target.key) == "Fix the login form",
            "The relaunch lost the link, pin or title")
        try require(await relaunched.loadRemoteSession(target.key), "The new conversation didn't reopen")
        try require(await relaunched.loadRemoteSession(source.key), "The earlier conversation didn't reopen")
        guard let reopened = relaunched.sessions.session(target.key),
            let earlier = relaunched.sessions.session(source.key)
        else { throw ChangeFailure("No models after relaunch") }
        try await wait("both conversations replay") {
            says(reopened, .user, sent) && says(earlier, .user, "Fix the login form")
        }
        try require(
            reopened.host?.client === againClient && earlier.host?.client === againClient
                && earlier.isEarlierConversation,
            "The reopened conversations aren't on the host, or the earlier one takes messages")
        try require(
            (await process.calls).filter { $0 == HostProtocol.Method.openSession }.count == opens + 2,
            "Relaunching opened the wrong sessions")
        try require((await process.started).count == 5, "Relaunching started a session")
        let relaunchedCalls = await hereAgain.calls
        try require(
            !relaunchedCalls.contains(HostProtocol.Method.newSession)
                && !relaunchedCalls.contains(HostProtocol.Method.openSession), "The relaunch opened a task on this Mac")
        print("PASS: after a relaunch both conversations reopen from the host, linked, pinned and titled")
        again.stop()
        await againClient.stop()
        await hereAgainClient.stop()
    }

    /// Opens Change Agent on the task's current conversation, for the next handoff.
    static func reviewTarget(_ app: AppModel, _ task: SessionModel) async throws -> ChangeAgentModel {
        app.requestAgentChange(task)
        guard let change = app.changingAgent else { throw ChangeFailure("Change Agent didn't open") }
        await change.loadContext()
        try require(change.agentID?.rawValue == "fixture", "The task's host offers the wrong agent")
        return change
    }
}
