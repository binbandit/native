import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration

// MARK: - The engine's runtime

extension HostTasks {
    var isReady: Bool { true }

    func taskAgents() -> [TaskAgent] {
        core.agentOrder.compactMap { core.agents[$0] }.map { link in
            let reason: String?
            if !core.policy.allows(agent: link.spec.id) || !core.allows(.agents) {
                reason = "This agent is disabled by organization policy."
            } else if link.hostAgent.needsSignIn || link.hostAgent.authStatus?.kind == .signedOut {
                reason = "This agent requires sign-in in Native."
            } else if link.hostAgent.state == .notInstalled || link.hostAgent.state == .failed {
                reason = "This agent is unavailable. Check its status in Native."
            } else {
                reason = nil
            }
            let observed =
                core.sessions.values.filter {
                    $0.record.agentID == link.spec.id && !$0.mirror.state.configOptions.isEmpty
                }
                .max { $0.record.createdAt < $1.record.createdAt }?.mirror.state.configOptions ?? []
            return TaskAgent(id: link.spec.id, name: link.spec.name, configOptions: observed, unavailableReason: reason)
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
        try checkParent(parent, request: request)
        let cwd = try await checkout(request.options.checkout, parent: parent)
        let template = launchTemplate(agent: request.agent.id, cwd: cwd, parent: parent)
        let summary = try await core.newSession(
            NewSessionParams(
                sessionID: HostSessionID(), agentID: request.agent.id, cwd: cwd, parentID: parent.id,
                origin: .task, mcpServers: template.servers, meta: template.meta))
        guard let session = core.sessions[summary.id], let agentSessionID = session.record.agentSessionID else {
            throw HostTaskError.parentClosed
        }
        do {
            try await prepare(session, request: request, parent: parent)
        } catch {
            try? await core.closeSession(session.id, closeInAgent: true)
            throw error
        }
        let task = OrchestrationTask(
            id: request.id, session: TaskSessionRef(agent: request.agent.id, id: agentSessionID.rawValue),
            agentName: request.agent.name, title: request.title, parent: request.parent,
            parentAgentName: request.parentAgentName, cwd: cwd, createdAt: .now)
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
                origin: .task),
            checking: { [self] in
                try checkParent(parent, request: request)
                try verifyPrepared(session, request: request, parent: parent)
            })
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
        guard let sender = session(holding: message.sender), let recipient = session(holding: message.recipient)
        else { throw HostTaskError.closed }
        try await core.load(recipient)
        guard let senderID = sender.record.agentSessionID, let recipientID = recipient.record.agentSessionID else {
            throw HostTaskError.closed
        }
        let delivery = try await core.prompt(
            PromptParams(
                sessionID: recipient.id, requestID: UUID(), text: message.prompt, behavior: .steer, echo: false,
                origin: .task),
            checking: { [self] in
                // Run inside the prompt transaction's task, after its last scheduling boundary.
                let coordinator = core.coordinators.first {
                    $0.task == HostTaskIdentity(sender) || $0.hostSessionID == sender.id
                }
                if let coordinator {
                    guard let target = HostTaskIdentity(recipient), coordinator.assignments.contains(target) else {
                        throw CoordinatorFailure("That task is no longer assigned to this coordinator.")
                    }
                }
                let text = coordinator == nil ? message.text : message.prompt
                core.append(.update(TaskTranscript.message(text, from: senderID, to: recipientID)), to: sender)
                core.append(.update(TaskTranscript.message(text, from: senderID, to: recipientID)), to: recipient)
            })
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
