import ACP
import Foundation
import MCP
import NativeHostProtocol
import NativeOrchestration

/// Native's tools for agents (the `native` MCP server), served by the host, and the tasks sessions
/// hand each other with them. The server listens on this machine's loopback, so on a remote host
/// the address is the remote machine's own, for its own agents. Each session reaches it at a URL
/// only it has: the token in it is the session's id with an HMAC from a secret only this host holds
/// (`MCPTokenSigner`), so a session id alone, which every client and the machine's processes may
/// know, gets nothing. The port and the secret are kept in the host's folder, and a session's URL
/// is worked out again at every load, so it's always this run's.
///
/// Tasks are sessions of the host like any other (origin `task`, the parent's id as parent): they
/// keep working with no client attached, and recover as any session does. Their cards live in their
/// parents' event logs, put back after every reload, so every client shows them the same way.
@HostActor
final class HostTasks {
    /// The server's name in agents' MCP lists.
    static let serverName = "native"

    unowned let core: HostCore
    private(set) var records: [OrchestrationTask]
    /// Whether sessions get Native's tools from here (`ConfigureTasksParams.servesTools`).
    private(set) var servesTools: Bool
    private var disabledSkills: [DisabledNativeSkill]
    #if canImport(Network) && canImport(CryptoKit)
    private let tokens = MCPTokens()
    private var server: MCPHTTPServer<OrchestrationCaller>?
    #endif
    private var starting: Task<Void, Never>?
    /// Waits for a session's turn to settle, by host session.
    private var waiters: [HostSessionID: [UUID: Waiter]] = [:]
    /// What each task's card last showed, by the task's host session, so it's sent only on change.
    private var cards: [HostSessionID: SubagentWorkState] = [:]
    /// The host's own tools, which the Mac app's `run_script` calls back into (`callTool`).
    var ownTools: [MCPTool<OrchestrationCaller>] = []
    /// Tools only the Mac app answers (`HostTasks+AppTools.swift`), and the client that offered them.
    var appTools: [AppToolDefinition]
    var appToolProvider: ClientLink.ID?
    /// Calls and listings passed to the app, waiting for its answer.
    var appToolCalls: [UUID: CheckedContinuation<AppToolResult?, Never>] = [:]

    private struct Waiter {
        let continuation: CheckedContinuation<Void, Never>
        let timer: Task<Void, Never>
    }

    init(core: HostCore) {
        self.core = core
        records = (try? core.store.tasks()) ?? []
        servesTools = Self.canServe && (try? core.store.meta(MetaKey.tasksServeTools)) != "0"
        disabledSkills =
            (try? core.store.meta(MetaKey.tasksDisabledSkills)).flatMap { $0 }.flatMap {
                try? JSONDecoder().decode([DisabledNativeSkill].self, from: Data($0.utf8))
            } ?? []
        appTools =
            (try? core.store.meta(MetaKey.tasksAppTools)).flatMap { $0 }.flatMap {
                try? JSONDecoder().decode([AppToolDefinition].self, from: Data($0.utf8))
            } ?? []
    }

    // MARK: - The server

    /// Whether this machine can serve the tools: the server needs Network and CryptoKit, which only
    /// Apple's platforms have so far.
    #if canImport(Network) && canImport(CryptoKit)
    static let canServe = true
    #else
    static let canServe = false
    #endif

    /// Starts listening, on the port this host had last run when it's free.
    func start() {
        guard starting == nil else { return }
        #if canImport(Network) && canImport(CryptoKit)
        let configuration = core.configuration
        let orchestrator = TaskOrchestrator(runtime: self)
        let skills = SkillTools.all(configuration.nativeSkills, pluginsFolder: configuration.pluginsDirectory) {
            skills, caller in
            await orchestrator.skills(skills, for: caller)
        }
        let tokens = tokens
        ownTools = OrchestrationTools.all(orchestrator) + skills
        let server = MCPHTTPServer(
            name: Self.serverName, version: configuration.hostInfo.version,
            instructions: OrchestrationTools.instructions, tools: ownTools,
            moreTools: { [weak self] _ in await self?.relayedTools() ?? [] }
        ) { [weak self] token in
            // The token is the only credential a caller presents; nothing this host didn't sign gets in.
            guard let client = tokens.client(in: token) else { return nil }
            return await self?.caller(of: client)
        }
        self.server = server
        let channel = configuration.location.channel
        let store = MCPServerStore(directory: configuration.location.directory.appending(path: "MCP"))
        let logger = core.logger
        starting = Task {
            do {
                let launch = try await server.start(remembering: store, scope: channel, tokens: tokens)
                if let failure = launch.storeFailure {
                    logger.error("Native's tool URLs won't outlast this run: \(failure)")
                }
            } catch {
                logger.error("Couldn't start Native's tools for agents: \(error.localizedDescription)")
            }
        }
        #else
        starting = Task {}
        core.logger.info("Native's tools for agents aren't available on this host yet.")
        #endif
    }

    /// The MCP servers to hand the agent for a session: `base` (what clients gave it), with Native's
    /// own entry at this run's address when the host serves the tools.
    func agentServers(for session: HostSessionID, base: [JSONValue]) async -> [JSONValue] {
        guard servesTools else { return base }
        #if canImport(Network) && canImport(CryptoKit)
        await starting?.value
        let others = base.filter { $0["name"]?.stringValue != Self.serverName }
        guard let url = tokens.token(for: session.rawValue).flatMap({ server?.url(for: $0) }),
            let entry = try? JSONDecoder().decode(
                JSONValue.self, from: JSONEncoder().encode(MCPServer.http(name: Self.serverName, url: url)))
        else { return others }
        return others + [entry]
        #else
        return base
        #endif
    }

    /// What a Mac app chose: who serves the tools, which of Native's skills are off, and the tools
    /// it answers itself.
    func configure(_ params: ConfigureTasksParams, from client: ClientLink.ID) throws {
        servesTools = Self.canServe && params.servesTools
        disabledSkills = params.disabledSkills
        appTools = params.appTools
        appToolProvider = params.appTools.isEmpty ? nil : client
        try core.store.setMeta(
            MetaKey.tasksAppTools, String(decoding: try JSONEncoder().encode(params.appTools), as: UTF8.self))
        try core.store.setMeta(MetaKey.tasksServeTools, params.servesTools ? "1" : "0")
        try core.store.setMeta(
            MetaKey.tasksDisabledSkills,
            String(decoding: try JSONEncoder().encode(params.disabledSkills), as: UTF8.self))
    }

    // MARK: - What clients see

    var hostTasks: [HostTask] {
        records.map(hostTask)
    }

    private func hostTask(_ task: OrchestrationTask) -> HostTask {
        HostTask(
            id: task.id, agentID: task.session.agent, agentSessionID: SessionID(task.session.id),
            agentName: task.agentName, title: task.title, cwd: task.cwd, parentAgentID: task.parent.agent,
            parentAgentSessionID: SessionID(task.parent.id), parentAgentName: task.parentAgentName,
            sessionID: session(holding: task.session)?.id, parentSessionID: session(holding: task.parent)?.id,
            createdAt: task.createdAt)
    }

    private func save(_ task: OrchestrationTask) throws {
        try core.store.saveTask(task)
        if let index = records.firstIndex(where: { $0.id == task.id }) {
            records[index] = task
        } else {
            records.append(task)
        }
        let notification = TaskChangedNotification(task: hostTask(task))
        for client in core.clients.values {
            client.notify(HostProtocol.Method.tasksChanged, notification)
        }
    }

    // MARK: - Following sessions

    /// A session's summary changed: wake whoever waits on it, and keep its card, if it's a task,
    /// in step.
    func sessionChanged(_ session: HostSession) {
        if let waiting = waiters[session.id], !waiting.isEmpty, snapshot(session, reading: false).status != .running {
            waiters[session.id] = nil
            for waiter in waiting.values {
                waiter.timer.cancel()
                waiter.continuation.resume()
            }
        }
        guard session.record.origin == .task, let ref = ref(of: session),
            let task = records.first(where: { $0.session == ref })
        else { return }
        showCard(of: task, session: session)
    }

    /// A session went away: no one waits on it any more.
    func sessionClosed(_ session: HostSession) {
        cards[session.id] = nil
        for waiter in (waiters.removeValue(forKey: session.id) ?? [:]).values {
            waiter.timer.cancel()
            waiter.continuation.resume()
        }
    }

    /// A session (re)loaded, which replaced its transcript: its tasks' cards go back in, opening
    /// tasks the host doesn't have so they're there to follow.
    func sessionLoaded(_ session: HostSession) {
        guard let ref = ref(of: session) else { return }
        for task in records where task.parent == ref {
            let child = self.session(holding: task.session) ?? adopt(task, parent: session)
            guard let child else { continue }
            cards[child.id] = nil
            showCard(of: task, session: child, titled: true)
        }
    }

    /// The agent never saved a session and the host carried it on in a fresh one: tasks it is, or
    /// started, follow it there.
    func agentSessionReplaced(agent: String, old: SessionID, new: SessionID) {
        let old = TaskSessionRef(agent: agent, id: old.rawValue)
        let new = TaskSessionRef(agent: agent, id: new.rawValue)
        for var task in records where task.session == old || task.parent == old {
            if task.session == old { task.session = new }
            if task.parent == old { task.parent = new }
            try? save(task)
        }
    }

    /// Puts the task's card in its parent's transcript (`titled`: with its title and agent, as it
    /// first appears), or moves it to the task's current state.
    private func showCard(of task: OrchestrationTask, session: HostSession, titled: Bool = false) {
        guard let parent = self.session(holding: task.parent), let agentSessionID = session.record.agentSessionID
        else { return }
        var state = snapshot(session, reading: false).workState
        if case .idle(.error, _) = state {
            // Why it failed is in its transcript.
            state = snapshot(session).workState
        }
        guard titled || cards[session.id] != state else { return }
        cards[session.id] = state
        let card = TaskTranscript.card(
            session: agentSessionID, title: titled ? task.title : nil, agentName: titled ? task.agentName : nil,
            state: state,
            meta: TaskTranscript.CardMeta(taskID: task.id, clientID: session.id.rawValue, agent: task.session.agent))
        core.append(.update(card), to: parent)
    }

    /// A task's session the host doesn't have, opened without loading: it loads when someone
    /// follows it or a tool needs it, as sessions do after the host restarts.
    private func adopt(_ task: OrchestrationTask, parent: HostSession) -> HostSession? {
        let cwd = task.cwd ?? parent.record.cwd
        let template = launchTemplate(agent: task.session.agent, cwd: cwd, parent: parent)
        let record = StoredSession(
            id: HostSessionID(), agentID: task.session.agent, agentSessionID: SessionID(task.session.id), cwd: cwd,
            parentID: parent.id, origin: .task, title: task.title, mcpServers: template.servers, meta: template.meta,
            isAdopted: true)
        do {
            try core.store.insertSession(record)
        } catch {
            core.logger.error("Couldn't reopen task \(task.id): \(error.localizedDescription)")
            return nil
        }
        let session = HostSession(
            record: record, agentName: core.agents[record.agentID]?.spec.name ?? task.agentName, phase: .idle,
            needsLoad: true, mcpServers: record.mcpServers)
        core.sessions[record.id] = session
        _ = session.append(.reset(loading: false))
        core.publish(session)
        return session
    }

    // MARK: - Lookups

    func session(holding ref: TaskSessionRef) -> HostSession? {
        core.sessions.values.first {
            $0.record.agentID == ref.agent && $0.record.agentSessionID?.rawValue == ref.id
                && $0.record.origin != .announced
        }
    }

    private func ref(of session: HostSession) -> TaskSessionRef? {
        session.record.agentSessionID.map { TaskSessionRef(agent: session.record.agentID, id: $0.rawValue) }
    }

    /// How the session reads as a task. The transcript is folded only when the state needs it.
    private func snapshot(_ session: HostSession, reading: Bool = true) -> TaskSnapshot {
        let phase: TaskSnapshot.Phase =
            switch session.phase {
            case .loading, .recovering: .loading
            case .prompting: .running
            case .disconnected: .disconnected
            case .idle, .unknown: session.turn != nil || session.retryAt != nil ? .running : .idle
            }
        let stopReason = session.record.lastStopReason.map(SessionMirror.stopReason)
        let needsApproval = !session.pendingPermissions.isEmpty || !session.pendingQuestions.isEmpty
        guard reading else {
            // The card only shows the reason a turn failed; anything else reads without the transcript.
            return TaskSnapshot(
                phase: phase, needsApproval: needsApproval, lastStopReason: stopReason, agentName: session.agentName,
                state: SessionState())
        }
        return TaskSnapshot(
            phase: phase, needsApproval: needsApproval, lastStopReason: stopReason, agentName: session.agentName,
            state: session.mirror.state)
    }

    /// What a session Native's tools start gets from plugins, which only clients know: the MCP servers
    /// and `_meta` a client last gave a session of the same agent in the same folder; else the
    /// parent's, when it runs on the same agent; else the parent's servers (they're the project's)
    /// without its `_meta` (that's its agent's). Native's own entry is added at load.
    func launchTemplate(agent: String, cwd: String, parent: HostSession) -> (servers: [JSONValue], meta: JSONValue?) {
        let mine = { (servers: [JSONValue]) in servers.filter { $0["name"]?.stringValue != Self.serverName } }
        let sibling = core.sessions.values.filter {
            $0.record.agentID == agent && $0.record.cwd == cwd && $0.record.origin != .announced
        }.max { $0.record.createdAt < $1.record.createdAt }
        if let sibling {
            return (mine(sibling.record.mcpServers), sibling.record.meta)
        }
        return (mine(parent.record.mcpServers), parent.record.agentID == agent ? parent.record.meta : nil)
    }
}

// MARK: - The engine's runtime

extension HostTasks: TaskRuntime {
    var isReady: Bool { true }

    func taskAgents() -> [TaskAgent] {
        core.agentOrder.compactMap { core.agents[$0] }.filter { $0.hostAgent.state != .notInstalled }.map {
            TaskAgent(id: $0.spec.id, name: $0.spec.name)
        }
    }

    func caller(of clientID: UUID) -> OrchestrationCaller? {
        guard let session = core.sessions[HostSessionID(clientID)], session.record.origin != .announced else {
            return nil
        }
        return OrchestrationCaller(
            clientID: clientID, agent: session.record.agentID,
            cwd: URL(filePath: session.record.cwd, directoryHint: .isDirectory))
    }

    func session(of clientID: UUID) -> TaskSessionRef? {
        core.sessions[HostSessionID(clientID)].flatMap(ref(of:))
    }

    func tasks() -> [OrchestrationTask] {
        records
    }

    func startTask(_ request: TaskRequest) async throws -> OrchestrationTask {
        guard let parent = session(holding: request.parent), let parentAgentSessionID = parent.record.agentSessionID
        else { throw HostTaskError.parentClosed }
        let template = launchTemplate(agent: request.agent.id, cwd: parent.record.cwd, parent: parent)
        let summary = try await core.newSession(
            NewSessionParams(
                sessionID: HostSessionID(), agentID: request.agent.id, cwd: parent.record.cwd, parentID: parent.id,
                origin: .task, mcpServers: template.servers, meta: template.meta))
        guard let session = core.sessions[summary.id], let agentSessionID = session.record.agentSessionID else {
            throw HostTaskError.parentClosed
        }
        let task = OrchestrationTask(
            id: request.id, session: TaskSessionRef(agent: request.agent.id, id: agentSessionID.rawValue),
            agentName: request.agent.name, title: request.title, parent: request.parent,
            parentAgentName: request.parentAgentName, cwd: parent.record.cwd, createdAt: .now)
        try save(task)
        session.record.title = request.title
        try? core.store.updateSession(session.record)
        // Recorded the way agents record their own subagents' tasks: in the task's transcript, from
        // its parent, while the parent's shows the task itself.
        core.append(
            .update(TaskTranscript.message(request.text, from: parentAgentSessionID, to: agentSessionID)), to: session)
        // Running from the first: the prompt goes out next.
        cards[session.id] = .running
        core.append(
            .update(
                TaskTranscript.card(
                    session: agentSessionID, title: task.title, agentName: task.agentName, state: .running,
                    meta: TaskTranscript.CardMeta(
                        taskID: task.id, clientID: session.id.rawValue, agent: task.session.agent))),
            to: parent)
        _ = try await core.prompt(
            PromptParams(
                sessionID: session.id, requestID: UUID(), text: request.prompt, behavior: .queue, echo: false,
                origin: .task))
        return task
    }

    func openTask(_ task: OrchestrationTask) async throws {
        let parent = session(holding: task.parent)
        let session =
            session(holding: task.session)
            ?? parent.flatMap { adopt(task, parent: $0) }
        guard let session else { throw HostTaskError.parentClosed }
        try await core.load(session)
        if parent != nil {
            cards[session.id] = nil
            showCard(of: task, session: session, titled: true)
        }
    }

    func snapshot(of ref: TaskSessionRef) -> TaskSnapshot? {
        session(holding: ref).map { snapshot($0) }
    }

    func settle(_ ref: TaskSessionRef, timeout: Duration) async {
        guard let session = session(holding: ref), snapshot(session, reading: false).status == .running else { return }
        let sessionID = session.id
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard !Task.isCancelled else { return continuation.resume() }
                let timer = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.stopWaiting(id, on: sessionID)
                }
                waiters[sessionID, default: [:]][id] = Waiter(continuation: continuation, timer: timer)
            }
        } onCancel: {
            Task { @HostActor [weak self] in self?.stopWaiting(id, on: sessionID) }
        }
    }

    private func stopWaiting(_ id: UUID, on session: HostSessionID) {
        guard let waiter = waiters[session]?.removeValue(forKey: id) else { return }
        waiter.timer.cancel()
        waiter.continuation.resume()
    }

    func deliver(_ message: TaskMessage) async throws -> TaskMessage.Delivery {
        guard let sender = session(holding: message.sender), let recipient = session(holding: message.recipient),
            let senderID = sender.record.agentSessionID, let recipientID = recipient.record.agentSessionID
        else { throw HostTaskError.closed }
        core.append(.update(TaskTranscript.message(message.text, from: senderID, to: recipientID)), to: sender)
        core.append(.update(TaskTranscript.message(message.text, from: senderID, to: recipientID)), to: recipient)
        let delivery = try await core.prompt(
            PromptParams(
                sessionID: recipient.id, requestID: UUID(), text: message.prompt, behavior: .steer, echo: false,
                origin: .task))
        return switch delivery {
        case .prompted: .prompted
        case .steered: .steered
        case .queued, .unknown: .queued
        }
    }

    func cancelTask(_ ref: TaskSessionRef) async {
        guard let session = session(holding: ref) else { return }
        await core.cancel(session)
    }

    func disabledSkills(of clientID: UUID) -> Set<String> {
        guard let session = core.sessions[HostSessionID(clientID)] else { return [] }
        return DisabledNativeSkill.off(in: session.record.cwd, disabledSkills)
    }
}

enum HostTaskError: LocalizedError {
    case parentClosed
    case closed
    case noTool(String)

    var errorDescription: String? {
        switch self {
        case .parentClosed: "The task that started the task is no longer open on the host."
        case .closed: "That task is no longer open on the host."
        case .noTool(let name): "The host has no tool named \(name)."
        }
    }
}

extension MetaKey {
    /// "0" when a Mac app serves Native's tools itself (`ConfigureTasksParams.servesTools`).
    static let tasksServeTools = "tasks_serve_tools"
    /// Native's skills switched off, as JSON (`ConfigureTasksParams.disabledSkills`).
    static let tasksDisabledSkills = "tasks_disabled_skills"
    /// The tools the Mac app answers, as JSON (`ConfigureTasksParams.appTools`).
    static let tasksAppTools = "tasks_app_tools"
}
