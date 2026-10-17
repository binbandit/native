import ACP
import Foundation
import Observation

extension OrchestrationPlugin {
    /// Lets the tools run tasks as `model`'s sessions.
    static func connect(to model: AppModel) {
        let plugin = model.plugins.plugins.lazy.compactMap { $0.plugin as? OrchestrationPlugin }.first
        plugin?.orchestrator.host = AppOrchestrationHost(model: model)
    }
}


/// Runs orchestration tasks as sessions of the app: each task is a session of its agent that its
/// parent delegated, shown in the parent's transcript as a subagent, with messages between
/// sessions recorded in both transcripts.
final class AppOrchestrationHost: OrchestrationHost {
    /// Weak because the model owns the plugins, which own this.
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    var taskAgents: [AgentDefinition] {
        model?.agents.filter(\.isReady).map(\.agent) ?? []
    }

    func startTask(_ request: TaskRequest) async throws -> UUID {
        let parent = try session(request.parent)
        guard let model else { throw HostError.closed }
        let task = try await model.startTaskSession(agent: request.agent, parent: request.parent)
        parent.apply(.subagent(SubagentUpdate(
            sessionId: task.id,
            title: .set(request.title ?? Self.headline(of: request.text)),
            description: .set(task.agentName),
            canCancel: .set(true),
            state: .set(.running)
        )))
        // Recorded the way agents record their own subagents' tasks: in the subagent's transcript,
        // from its parent, while the parent's shows the subagent itself.
        task.apply(.sessionMessage(Self.message(request.text, from: parent, to: task)))
        try await task.submit(request.prompt, .queue, echo: false)
        mirror(task, into: parent)
        return task.clientID
    }

    func taskSnapshot(_ session: UUID) -> TaskSnapshot? {
        model?.session(clientID: session).map(Self.snapshot)
    }

    func deliver(_ message: TaskMessage) async throws -> TaskMessage.Delivery {
        let sender = try session(message.sender)
        let recipient = try session(message.recipient)
        guard recipient.phase == .idle || recipient.phase == .prompting else { throw HostError.unavailable(recipient.agentName) }
        sender.apply(.sessionMessage(Self.message(message.text, from: sender, to: recipient)))
        recipient.apply(.sessionMessage(Self.message(message.text, from: sender, to: recipient)))
        return switch try await recipient.submit(message.prompt, .steer, echo: false) {
        case .prompted: .prompted
        case .steered: .steered
        case .queued: .queued
        }
    }

    func cancelTask(_ task: UUID) async {
        await model?.session(clientID: task)?.cancel()
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
            case .error: return TaskSnapshot(status: .failed, reply: reply, detail: session.state.lastErrorNotice ?? "The turn failed.")
            case .maxTokens: return TaskSnapshot(status: .idle, reply: reply, detail: "stopped at the token limit")
            case .maxTurnRequests: return TaskSnapshot(status: .idle, reply: reply, detail: "stopped at the turn's request limit")
            case .refusal: return TaskSnapshot(status: .idle, reply: reply, detail: "the agent declined to continue")
            case .other(let reason): return TaskSnapshot(status: .idle, reply: reply, detail: "stopped: \(reason)")
            }
        }
    }

    /// Keeps the parent's card for a task in step with the task, as an agent reports its own
    /// subagents' work, for as long as the task is open.
    private func mirror(_ task: SessionModel, into parent: SessionModel) {
        let states = Observations { [weak task] in task.map { Self.workState(Self.snapshot(of: $0)) } }
        let id = task.id
        Task { [weak parent] in
            var reported: SubagentWorkState? = .running
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
        case .failed: .idle(stopReason: .error, error: RPCError(code: 0, message: snapshot.detail ?? "The task failed."))
        }
    }

    // MARK: - Helpers

    private func session(_ clientID: UUID) throws -> SessionModel {
        guard let session = model?.session(clientID: clientID) else { throw HostError.closed }
        return session
    }

    /// Every transcript gets its own copy of a message, so each needs its own id.
    private static func message(_ text: String, from sender: SessionModel, to recipient: SessionModel) -> SessionMessageUpdate {
        SessionMessageUpdate(messageId: "native-\(UUID().uuidString)", senderSessionId: sender.id, recipientSessionId: recipient.id, content: [.text(text)])
    }

    /// A title for a task the calling agent didn't name: the start of its first line.
    private static func headline(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }

    private enum HostError: LocalizedError {
        case closed
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .closed: "That session is no longer open in Native."
            case .unavailable(let agent): "That session can't take messages right now: it's loading, or \(agent) stopped running."
            }
        }
    }
}
