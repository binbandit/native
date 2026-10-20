import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeSetup
import Observation

extension OrchestrationPlugin {
    /// Lets the tools run tasks as `model`'s sessions, and report how Native is set up. With a host,
    /// its sessions get this launch's URLs for their next load.
    static func connect(to model: AppModel, updates: UpdateController?, durableHost: DurableHost?) {
        guard let plugin = model.plugins.plugins.lazy.compactMap({ $0.plugin as? OrchestrationPlugin }).first else {
            return
        }
        plugin.orchestrator.host = AppOrchestrationHost(
            model: model, durableHost: durableHost,
            setup: AppSetupReporter(model: model, updates: updates, durableHost: durableHost))
        if let durableHost {
            Task { await plugin.refreshURLs(in: durableHost, plugins: model.plugins) }
        }
    }
}

/// Runs orchestration tasks as sessions of the app: each task is a session of its agent that its
/// parent delegated, shown in the parent's transcript as a subagent, with messages between
/// sessions recorded in both transcripts.
final class AppOrchestrationHost: OrchestrationHost {
    /// Weak because the model owns the plugins, which own this.
    private weak var model: AppModel?
    private weak var durableHost: DurableHost?
    /// Tasks whose card already follows them, so reopening one twice doesn't double up.
    private var mirrored: Set<SessionKey> = []
    private let setup: AppSetupReporter

    init(model: AppModel, durableHost: DurableHost?, setup: AppSetupReporter) {
        self.model = model
        self.durableHost = durableHost
        self.setup = setup
    }

    var taskAgents: [AgentDefinition] {
        model?.agents.filter(\.isAvailable).map(\.agent) ?? []
    }

    func sessionKey(of clientID: UUID) -> SessionKey? {
        model?.session(clientID: clientID)?.key
    }

    func caller(of clientID: UUID) async -> OrchestrationCaller? {
        if let session = model?.session(clientID: clientID) {
            return OrchestrationCaller(clientID: clientID, agent: session.agent.id, cwd: session.cwd)
        }
        // A host session the app hasn't opened, such as a task working while its parent is closed.
        // Right after launch the host's list may not be in yet, so ask it then.
        var summary = durableHost?.sessions.first { $0.id.rawValue == clientID }
        if summary == nil, let client = durableHost?.client {
            summary = try? await client.sessions().first { $0.id.rawValue == clientID }
        }
        return summary.map {
            OrchestrationCaller(
                clientID: clientID, agent: AgentDefinition.ID(rawValue: $0.agentID),
                cwd: URL(filePath: $0.cwd, directoryHint: .isDirectory))
        }
    }

    func disabledSkills(of clientID: UUID) -> Set<String> {
        guard let model, let session = model.session(clientID: clientID) else { return [] }
        return Set(model.plugins.sessionPolicy(for: session.context).disabledSkills.compactMap(\.name))
    }

    func setupReport(callerAgent: AgentDefinition.ID) async -> SetupReport {
        await setup.report(callerAgent: callerAgent)
    }

    func startTask(_ request: TaskRequest) async throws -> SessionKey {
        let parent = try session(request.parent)
        guard let model else { throw HostError.closed }
        let task = try await model.startTaskSession(agent: request.agent, parent: parent.clientID)
        // Recorded the way agents record their own subagents' tasks: in the subagent's transcript,
        // from its parent, while the parent's shows the subagent itself.
        task.apply(.sessionMessage(Self.message(request.text, from: parent, to: task)))
        try await task.submit(request.prompt, .queue, echo: false)
        show(task, titled: request.title, in: parent)
        return task.key
    }

    func openTask(_ record: OrchestrationTask) async throws {
        guard let model, model.session(record.session) == nil else { return }
        let parent = try session(record.parent)
        // A card applied while the parent replays its history would land in the middle of it.
        await Self.loaded(parent)
        let task = try await model.reopenTaskSession(
            agent: record.session.agent, id: record.session.id, cwd: parent.cwd)
        await Self.loaded(task)
        show(task, titled: record.title, in: parent)
    }

    func taskSnapshot(_ session: SessionKey) -> TaskSnapshot? {
        model?.session(session).map(Self.snapshot)
    }

    func deliver(_ message: TaskMessage) async throws -> TaskMessage.Delivery {
        let sender = try session(message.sender)
        let recipient = try session(message.recipient)
        guard recipient.phase == .idle || recipient.phase == .prompting else {
            throw HostError.unavailable(recipient.agentName)
        }
        sender.apply(.sessionMessage(Self.message(message.text, from: sender, to: recipient)))
        recipient.apply(.sessionMessage(Self.message(message.text, from: sender, to: recipient)))
        return switch try await recipient.submit(message.prompt, .steer, echo: false) {
        case .prompted: .prompted
        case .steered: .steered
        case .queued: .queued
        }
    }

    func cancelTask(_ task: SessionKey) async {
        await model?.session(task)?.cancel()
    }

    // MARK: - Snapshots

    private static func snapshot(of session: SessionModel) -> TaskSnapshot {
        let reply = session.state.latestReply
        switch session.phase {
        case .loading:
            return TaskSnapshot(status: .running)
        case .prompting where session.needsApproval:
            return TaskSnapshot(status: .needsApproval, reply: reply, detail: session.state.awaitingApproval)
        case .prompting:
            return TaskSnapshot(status: .running, reply: reply)
        case .disconnected:
            return TaskSnapshot(status: .failed, reply: reply, detail: "\(session.agentName) stopped running.")
        case .idle:
            switch session.lastStopReason {
            case nil, .endTurn: return TaskSnapshot(status: .idle, reply: reply)
            case .cancelled: return TaskSnapshot(status: .cancelled, reply: reply)
            case .error:
                return TaskSnapshot(
                    status: .failed, reply: reply, detail: session.state.lastErrorNotice ?? "The turn failed.")
            case .maxTokens: return TaskSnapshot(status: .idle, reply: reply, detail: "stopped at the token limit")
            case .maxTurnRequests:
                return TaskSnapshot(status: .idle, reply: reply, detail: "stopped at the turn's request limit")
            case .refusal: return TaskSnapshot(status: .idle, reply: reply, detail: "the agent declined to continue")
            case .other(let reason): return TaskSnapshot(status: .idle, reply: reply, detail: "stopped: \(reason)")
            }
        }
    }

    /// Puts the task's card in the parent's transcript and keeps it in step with the task, as an
    /// agent reports its own subagents' work, for as long as the task is open.
    private func show(_ task: SessionModel, titled title: String, in parent: SessionModel) {
        let state = Self.workState(Self.snapshot(of: task))
        parent.apply(
            .subagent(
                SubagentUpdate(
                    sessionId: task.id, title: .set(title), description: .set(task.agentName), canCancel: .set(true),
                    state: .set(state))))
        guard mirrored.insert(task.key).inserted else { return }
        let states = Observations { [weak task] in task.map { Self.workState(Self.snapshot(of: $0)) } }
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

    private static func workState(_ snapshot: TaskSnapshot) -> SubagentWorkState {
        switch snapshot.status {
        case .running: .running
        case .needsApproval: .requiresAction
        case .idle: .idle(stopReason: .endTurn, error: nil)
        case .cancelled: .idle(stopReason: .cancelled, error: nil)
        case .failed:
            .idle(stopReason: .error, error: RPCError(code: 0, message: snapshot.detail ?? "The task failed."))
        }
    }

    // MARK: - Helpers

    private func session(_ key: SessionKey) throws -> SessionModel {
        guard let session = model?.session(key) else { throw HostError.closed }
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

    private enum HostError: LocalizedError {
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
