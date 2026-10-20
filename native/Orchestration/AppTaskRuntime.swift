import ACP
import Foundation
import MCP
import NativeHostClient
import NativeHostProtocol
import NativeOrchestration
import NativeSetup
import Observation
import os

/// Runs orchestration tasks as sessions of the app, for when the app serves Native's tools itself:
/// agents running inside it, or a host told to leave the tools to it (`HostTasks`). Each task is a
/// session of its agent that its parent delegated, shown in the parent's transcript as a subagent,
/// with messages between sessions recorded in both transcripts. Tasks are remembered in the user
/// defaults, and reopened when their parent is or when a tool needs one.
final class AppTaskRuntime {
    /// Weak because the model owns the plugins, which own this. Nil until the app is up; the tools
    /// say to try again meanwhile.
    weak var model: AppModel?
    weak var durableHost: DurableHost?
    /// What `setup_status` reports from.
    var setup: AppSetupReporter?
    /// The sessions handed a URL this launch, by Native's id for them (`SessionContext.clientID`),
    /// which is what their tokens name.
    private var callers: [UUID: OrchestrationCaller] = [:]
    /// In the order they started.
    private var records: [OrchestrationTask] {
        didSet { save() }
    }
    /// Tasks whose card already follows them, so reopening one twice doesn't double up.
    private var mirrored: Set<SessionKey> = []
    private let defaults: UserDefaults
    static let tasksKey = "orchestrationTasks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = Self.savedTasks(in: defaults)
    }

    static func savedTasks(in defaults: UserDefaults) -> [OrchestrationTask] {
        defaults.data(forKey: tasksKey).flatMap { try? JSONDecoder().decode([OrchestrationTask].self, from: $0) } ?? []
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.tasksKey)
        }
    }

    /// Notes that `session` is being handed its URL, so its token resolves to it. The first time in
    /// a launch for a session the agent already has (one being reopened), its tasks reopen too, so
    /// its transcript shows them again.
    func handedURL(to session: SessionContext) {
        let caller = OrchestrationCaller(clientID: session.clientID, agent: session.agent.rawValue, cwd: session.cwd)
        guard callers.updateValue(caller, forKey: session.clientID) == nil, let id = session.sessionID else { return }
        let parent = TaskSessionRef(SessionKey(agent: session.agent, id: id))
        let children = records.filter { $0.parent == parent }
        guard !children.isEmpty else { return }
        Task {
            for task in children {
                try? await openTask(task)
            }
        }
    }

    /// How Native is set up on this Mac, for `setup_status`, with the caller's agent marked.
    func setupReport(callerAgent: String) async throws -> SetupReport {
        guard let setup else { throw MCPToolError("Native isn't ready yet. Try again shortly.") }
        return await setup.report(callerAgent: AgentDefinition.ID(rawValue: callerAgent))
    }

    // MARK: - TaskRuntime

    var isReady: Bool { model != nil }

    func taskAgents() -> [TaskAgent] {
        model?.agents.filter(\.isAvailable).map { TaskAgent(id: $0.agent.id.rawValue, name: $0.agent.displayName) }
            ?? []
    }

    func caller(of clientID: UUID) async -> OrchestrationCaller? {
        if let caller = callers[clientID] {
            return caller
        }
        if let session = model?.session(clientID: clientID) {
            return OrchestrationCaller(clientID: clientID, agent: session.agent.id.rawValue, cwd: session.cwd)
        }
        // A host session the app hasn't opened, such as a task working while its parent is closed.
        // Right after launch the host's list may not be in yet, so ask it then.
        var summary = durableHost?.sessions.first { $0.id.rawValue == clientID }
        if summary == nil, let client = durableHost?.client {
            summary = try? await client.sessions().first { $0.id.rawValue == clientID }
        }
        return summary.map {
            OrchestrationCaller(
                clientID: clientID, agent: $0.agentID, cwd: URL(filePath: $0.cwd, directoryHint: .isDirectory))
        }
    }

    func session(of clientID: UUID) -> TaskSessionRef? {
        model?.session(clientID: clientID).map { TaskSessionRef($0.key) }
    }

    func tasks() -> [OrchestrationTask] {
        records
    }

    func startTask(_ request: TaskRequest) async throws -> OrchestrationTask {
        let parent = try session(request.parent)
        guard let model else { throw RuntimeError.closed }
        let task = try await model.startTaskSession(
            agent: AgentDefinition.ID(rawValue: request.agent.id), parent: parent.clientID)
        // Recorded the way agents record their own subagents' tasks: in the subagent's transcript,
        // from its parent, while the parent's shows the subagent itself.
        task.apply(.sessionMessage(Self.message(request.text, from: parent, to: task)))
        try await task.submit(request.prompt, .queue, echo: false)
        show(task, titled: request.title, in: parent)
        let record = OrchestrationTask(
            id: request.id, session: TaskSessionRef(task.key), agentName: request.agent.name, title: request.title,
            parent: request.parent, parentAgentName: request.parentAgentName, cwd: parent.cwd.folderPath,
            createdAt: .now)
        records.append(record)
        return record
    }

    func openTask(_ record: OrchestrationTask) async throws {
        let key = SessionKey(record.session)
        guard let model, model.session(key) == nil else { return }
        let parent = try session(record.parent)
        // A card applied while the parent replays its history would land in the middle of it.
        await Self.loaded(parent)
        let task = try await model.reopenTaskSession(agent: key.agent, id: key.id, cwd: parent.cwd)
        await Self.loaded(task)
        show(task, titled: record.title, in: parent)
    }

    func snapshot(of session: TaskSessionRef) -> TaskSnapshot? {
        model?.session(SessionKey(session)).map(Self.snapshot)
    }

    func settle(_ session: TaskSessionRef, timeout: Duration) async {
        let key = SessionKey(session)
        let statuses = Observations { [weak self] in self?.model?.session(key).map(Self.snapshot)?.status }
        await withTaskGroup { group in
            group.addTask {
                for await status in statuses where status != .running {
                    return
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            await group.next()
            group.cancelAll()
        }
    }

    func deliver(_ message: TaskMessage) async throws -> TaskMessage.Delivery {
        let sender = try session(message.sender)
        let recipient = try session(message.recipient)
        guard recipient.phase == .idle || recipient.phase == .prompting else {
            throw RuntimeError.unavailable(recipient.agentName)
        }
        sender.apply(.sessionMessage(Self.message(message.text, from: sender, to: recipient)))
        recipient.apply(.sessionMessage(Self.message(message.text, from: sender, to: recipient)))
        return switch try await recipient.submit(message.prompt, .steer, echo: false) {
        case .prompted: .prompted
        case .steered: .steered
        case .queued: .queued
        }
    }

    func cancelTask(_ task: TaskSessionRef) async {
        await model?.session(SessionKey(task))?.cancel()
    }

    func disabledSkills(of clientID: UUID) -> Set<String> {
        guard let model, let session = model.session(clientID: clientID) else { return [] }
        return Set(model.plugins.sessionPolicy(for: session.context).disabledSkills.compactMap(\.name))
    }

    // MARK: - Cards

    static func snapshot(of session: SessionModel) -> TaskSnapshot {
        let phase: TaskSnapshot.Phase =
            switch session.phase {
            case .loading: .loading
            case .prompting: .running
            case .idle: .idle
            case .disconnected: .disconnected
            }
        return TaskSnapshot(
            phase: phase, needsApproval: session.needsApproval, lastStopReason: session.lastStopReason,
            agentName: session.agentName, state: session.state)
    }

    /// Puts the task's card in the parent's transcript and keeps it in step with the task, as an
    /// agent reports its own subagents' work, for as long as the task is open.
    private func show(_ task: SessionModel, titled title: String, in parent: SessionModel) {
        let state = Self.snapshot(of: task).workState
        parent.apply(
            .subagent(
                SubagentUpdate(
                    sessionId: task.id, title: .set(title), description: .set(task.agentName), canCancel: .set(true),
                    state: .set(state))))
        guard mirrored.insert(task.key).inserted else { return }
        let states = Observations { [weak task] in task.map { Self.snapshot(of: $0).workState } }
        let id = task.id
        Task { [weak parent] in
            var reported: SubagentWorkState? = state
            for await state in states {
                guard let state, let parent else { return }
                guard state != reported else { continue }
                reported = state
                parent.apply(.subagent(SubagentUpdate(sessionId: id, state: .set(state))))
            }
        }
    }

    // MARK: - Helpers

    private func session(_ ref: TaskSessionRef) throws -> SessionModel {
        guard let session = model?.session(SessionKey(ref)) else { throw RuntimeError.closed }
        return session
    }

    private static func loaded(_ session: SessionModel) async {
        for await phase in Observations({ session.phase }) where phase != .loading {
            return
        }
    }

    /// Every transcript gets its own copy of a message, so each needs its own id.
    private static func message(
        _ text: String, from sender: SessionModel, to recipient: SessionModel
    ) -> SessionMessageUpdate {
        SessionMessageUpdate(
            messageId: "native-\(UUID().uuidString)", senderSessionId: sender.id, recipientSessionId: recipient.id,
            content: [.text(text)])
    }

    private enum RuntimeError: LocalizedError {
        case closed
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .closed: "That session is no longer open in Native."
            case .unavailable(let agent):
                "That session can't take messages right now: it's loading, or \(agent) stopped running."
            }
        }
    }
}

/// The engine's runtime over the app's sessions, on the main actor where they live.
nonisolated struct AppTaskRuntimeAdapter: TaskRuntime {
    let base: AppTaskRuntime

    var isReady: Bool {
        get async { await base.isReady }
    }

    func taskAgents() async -> [TaskAgent] { await base.taskAgents() }
    func caller(of clientID: UUID) async -> OrchestrationCaller? { await base.caller(of: clientID) }
    func session(of clientID: UUID) async -> TaskSessionRef? { await base.session(of: clientID) }
    func tasks() async -> [OrchestrationTask] { await base.tasks() }
    func startTask(_ request: TaskRequest) async throws -> OrchestrationTask { try await base.startTask(request) }
    func openTask(_ task: OrchestrationTask) async throws { try await base.openTask(task) }
    func snapshot(of session: TaskSessionRef) async -> TaskSnapshot? { await base.snapshot(of: session) }
    func settle(_ session: TaskSessionRef, timeout: Duration) async { await base.settle(session, timeout: timeout) }
    func deliver(_ message: TaskMessage) async throws -> TaskMessage.Delivery { try await base.deliver(message) }
    func cancelTask(_ session: TaskSessionRef) async { await base.cancelTask(session) }
    func disabledSkills(of clientID: UUID) async -> Set<String> { await base.disabledSkills(of: clientID) }
}

extension TaskSessionRef {
    init(_ key: SessionKey) {
        self.init(agent: key.agent.rawValue, id: key.id.rawValue)
    }
}

extension SessionKey {
    init(_ ref: TaskSessionRef) {
        self.init(agent: AgentDefinition.ID(rawValue: ref.agent), id: SessionID(ref.id))
    }
}
