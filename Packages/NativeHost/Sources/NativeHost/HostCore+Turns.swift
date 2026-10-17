import ACP
import Foundation
import NativeHostProtocol

// Turns: prompting, the queue of messages sent while a turn runs, steering, cancelling and
// answering permission requests. Every turn is committed to the store before its prompt is written
// to the agent, which is what lets recovery find it again.
extension HostCore {
    /// Delivers a message: as a new turn when the session is idle, otherwise steered into the running
    /// turn or queued. A request id seen before gets the same answer and is never delivered twice.
    func prompt(_ params: PromptParams) async throws -> PromptDelivery {
        if let delivery = try store.delivery(for: params.requestID) {
            return delivery
        }
        let session = try session(params.sessionID)
        guard session.record.origin != .announced else { throw HostError.notAcceptingPrompts }
        let text = params.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw HostError.emptyMessage }
        let item = QueuedPrompt(id: params.requestID, text: text, isEchoed: params.echo)
        switch session.phase {
        case .idle where session.turn == nil:
            // The user sending again lifts a pause after a cancelled turn; waiting messages go first.
            if !session.queue.isEmpty {
                session.queue.append(StoredQueueItem(prompt: item, isSteering: false))
                session.record.isQueuePaused = false
                try store.transaction {
                    try store.setQueue(session.queue, for: session.id)
                    try store.updateSession(session.record)
                    try store.recordDelivery(.queued, for: params.requestID, in: session.id)
                }
                drainQueue(session)
                publish(session)
                return .queued
            }
            try startTurn(in: session, prompt: item, origin: params.origin)
            return .prompted
        case .prompting where params.behavior == .steer && session.supportsSteering:
            return try await steer(item, into: session)
        default:
            try enqueue(item, in: session)
            if session.phase == .disconnected {
                // A message for a session whose agent couldn't run is a cue to try again.
                Task { try? await load(session) }
            }
            return .queued
        }
    }

    func enqueue(_ item: QueuedPrompt, in session: HostSession, atFront: Bool = false, steering: Bool = false) throws {
        let stored = StoredQueueItem(prompt: item, isSteering: steering)
        if atFront {
            session.queue.insert(stored, at: 0)
        } else {
            session.queue.append(stored)
        }
        try store.transaction {
            try store.setQueue(session.queue, for: session.id)
            try store.recordDelivery(.queued, for: item.id, in: session.id)
        }
        publish(session)
    }

    /// Commits the turn, then runs it in the background: the session is prompting when this returns.
    func startTurn(
        in session: HostSession, prompt: QueuedPrompt, origin: PromptEcho.Origin, kind: UnfinishedTurn.Kind = .prompt,
        attempts: Int = 0
    ) throws {
        let turn = UnfinishedTurn(
            sessionID: session.id, requestID: prompt.id, text: prompt.text, kind: kind, echo: prompt.isEchoed,
            attempts: attempts)
        session.record.lastActivity = .now
        try store.transaction {
            try store.beginTurn(turn)
            try store.recordDelivery(.prompted, for: prompt.id, in: session.id)
            try store.setQueue(session.queue, for: session.id)
            try store.updateSession(session.record)
        }
        session.turn = turn
        session.phase = .prompting
        if prompt.isEchoed {
            append(.prompt(PromptEcho(text: prompt.text, origin: origin)), to: session)
        }
        publish(session)
        Task { await run(turn, in: session) }
    }

    private func run(_ turn: UnfinishedTurn, in session: HostSession) async {
        do {
            try await load(session)
        } catch {
            // The turn stays committed; it runs once the agent can (see `prompt`, `load`).
            return
        }
        guard session.turn?.requestID == turn.requestID, let link = agents[session.record.agentID],
            let peer = link.peer,
            let agentSessionID = session.record.agentSessionID
        else { return }
        let generation = link.generation
        do {
            let response = try await peer.request(
                "session/prompt", PromptRequest(sessionId: agentSessionID, prompt: [.text(turn.text)]),
                as: RawPromptResponse.self
            )
            finish(turn, in: session, stopReason: response.stopReason)
        } catch PeerError.closed {
            // The agent died mid-turn; recovery takes it from here.
            agentExited(session.record.agentID, generation: generation)
        } catch {
            fail(turn, in: session, error: error)
        }
    }

    func finish(_ turn: UnfinishedTurn, in session: HostSession, stopReason: String) {
        guard session.turn?.requestID == turn.requestID else { return }
        // Queued messages wait out a cancelled turn until the user sends again.
        let pause = stopReason == "cancelled"
        endTurn(in: session, stopReason: stopReason, pauseQueue: pause)
        append(.turnEnded(stopReason: stopReason), to: session)
        if stopReason == "end_turn", session.record.parentID == nil {
            journal(.turnFinished, session: session)
        }
        publish(session)
        if !pause {
            drainQueue(session)
        }
        exitIfIdleForRestart()
    }

    private func fail(_ turn: UnfinishedTurn, in session: HostSession, error: any Error) {
        guard session.turn?.requestID == turn.requestID else { return }
        // An error isn't a stop reason; draining the queue after one could burn through all of it.
        endTurn(in: session, stopReason: "error", pauseQueue: true)
        let message = UsageLimitHit(error: error).map(\.message) ?? error.localizedDescription
        append(.turnFailed(message: message), to: session)
        journal(.turnFailed, session: session, detail: message)
        publish(session)
        exitIfIdleForRestart()
    }

    func endTurn(in session: HostSession, stopReason: String, pauseQueue: Bool) {
        session.turn = nil
        session.phase = .idle
        session.record.lastStopReason = stopReason
        session.record.isQueuePaused = pauseQueue
        withdrawPermissions(of: session)
        try? store.transaction {
            try store.finishTurn(session.id)
            try store.updateSession(session.record)
        }
    }

    /// Starts the next queued message once nothing is running, one per turn, unless paused.
    func drainQueue(_ session: HostSession) {
        guard session.phase == .idle, session.turn == nil, !session.record.isQueuePaused,
            let index = session.queue.firstIndex(where: { !$0.isSteering })
        else { return }
        let next = session.queue.remove(at: index)
        do {
            try startTurn(in: session, prompt: next.prompt, origin: .queued)
        } catch {
            session.queue.insert(next, at: index)
            logger.error("Couldn't start a queued turn: \(error.localizedDescription)")
        }
    }

    /// Adds a message to the running turn. It's recorded as steering first, so if the host stops
    /// before the agent answers, recovery can tell whether it arrived.
    private func steer(_ item: QueuedPrompt, into session: HostSession) async throws -> PromptDelivery {
        try enqueue(item, in: session, atFront: true, steering: true)
        var delivery = PromptDelivery.queued
        if let link = agents[session.record.agentID], let peer = link.peer,
            let agentSessionID = session.record.agentSessionID
        {
            do {
                let response = try await peer.request(
                    "_session/steering", SteerRequest(sessionId: agentSessionID, prompt: [.text(item.text)]),
                    as: RawSteerResponse.self
                )
                switch response.outcome {
                case "injected", "startedNewTurn":
                    // An older agent takes it as a new turn of its own; either way it's delivered.
                    session.queue.removeAll { $0.prompt.id == item.id }
                    if item.isEchoed {
                        append(
                            .prompt(PromptEcho(text: item.text, steered: response.outcome == "injected")), to: session)
                    }
                    delivery = .steered
                default:
                    // The turn ended first; it goes out next, ahead of what was already waiting.
                    break
                }
            } catch {
                append(
                    .notice(
                        text:
                            "Couldn't add your message to the running turn, so it's queued: \(error.localizedDescription)",
                        isError: true), to: session)
            }
        }
        if let index = session.queue.firstIndex(where: { $0.prompt.id == item.id }) {
            session.queue[index].isSteering = false
        }
        try store.transaction {
            try store.setQueue(session.queue, for: session.id)
            try store.recordDelivery(delivery, for: item.id, in: session.id)
        }
        publish(session)
        // The turn may have ended while the steer was in flight, leaving nothing to send the queue.
        drainQueue(session)
        return delivery
    }

    /// Cancels the running turn, or the recovery of one.
    func cancel(_ session: HostSession) async {
        guard let turn = session.turn else { return }
        let link = agents[session.record.agentID]
        if session.phase == .prompting, let peer = link?.peer, let agentSessionID = session.record.agentSessionID {
            // ACP requires answering open permission requests as cancelled when a turn is cancelled.
            for (_, requestID) in session.pendingPermissions {
                try? peer.respond(to: requestID, with: RequestPermissionResponse.cancelled)
            }
            withdrawPermissions(of: session)
            try? peer.notify("session/cancel", CancelNotification(sessionId: agentSessionID))
        } else {
            // Nothing is running to cancel (the agent is being restarted); just let the turn go.
            session.isRecoveryCancelled = true
            finish(turn, in: session, stopReason: "cancelled")
        }
    }

    func respondPermission(_ params: RespondPermissionParams) throws {
        let session = try session(params.sessionID)
        guard let requestID = session.pendingPermissions.removeValue(forKey: params.toolCallID) else {
            throw HostError.permissionNotPending
        }
        let response = params.optionID.map { RequestPermissionResponse.selected(optionId: $0) } ?? .cancelled
        try? agents[session.record.agentID]?.peer?.respond(to: requestID, with: response)
        append(.permissionResolved(toolCallID: params.toolCallID, optionID: params.optionID), to: session)
        try? store.removeApproval(sessionID: session.id, toolCallID: params.toolCallID)
        publish(session)
    }

    /// Drops permission requests that can't be answered any more (the turn ended, or the agent died).
    func withdrawPermissions(of session: HostSession) {
        for toolCallID in session.pendingPermissions.keys.sorted() {
            append(.permissionResolved(toolCallID: toolCallID, optionID: nil), to: session)
        }
        session.pendingPermissions = [:]
        try? store.removeApprovals(sessionID: session.id)
    }

    func setConfigOption(_ params: SetConfigOptionParams) async throws {
        let session = try session(params.sessionID)
        try await load(session)
        guard let peer = agents[session.record.agentID]?.peer, let agentSessionID = session.record.agentSessionID else {
            throw HostError.agentUnavailable(session.agentName)
        }
        let response = try await peer.request(
            "session/set_config_option",
            RawSetConfigOptionRequest(sessionId: agentSessionID, configId: params.configID, value: params.value),
            as: RawConfigOptionsResponse.self
        )
        if let options = response.configOptions {
            append(.update(SessionMirror.configOptionsUpdate(options)), to: session)
        }
    }

    // MARK: - Queue edits

    func updateQueued(_ params: QueueItemParams) throws {
        let session = try session(params.sessionID)
        guard let index = session.queue.firstIndex(where: { $0.prompt.id == params.itemID }) else { return }
        let text = params.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            session.queue.remove(at: index)
        } else {
            session.queue[index].prompt.text = text
        }
        try store.setQueue(session.queue, for: session.id)
        publish(session)
    }

    func removeQueued(_ params: QueueItemParams) throws {
        let session = try session(params.sessionID)
        session.queue.removeAll { $0.prompt.id == params.itemID }
        try store.setQueue(session.queue, for: session.id)
        publish(session)
    }

    /// Sends a queued message now instead of waiting: into the running turn, or as the next prompt
    /// when the session is idle (as it is after a cancelled turn paused the queue).
    func sendQueuedNow(_ params: QueueItemParams) async throws {
        let session = try session(params.sessionID)
        guard let index = session.queue.firstIndex(where: { $0.prompt.id == params.itemID }) else { return }
        if session.phase == .prompting, session.supportsSteering {
            let item = session.queue.remove(at: index)
            try store.setQueue(session.queue, for: session.id)
            _ = try await steer(item.prompt, into: session)
        } else if session.phase == .idle, session.turn == nil {
            let item = session.queue.remove(at: index)
            session.record.isQueuePaused = false
            try startTurn(in: session, prompt: item.prompt, origin: .queued)
        }
    }
}
