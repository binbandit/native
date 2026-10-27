import ACP
import Foundation
import NativeHostProtocol

// Turns: prompting, steering, settings and hidden commands. Every turn is committed to the store
// before its prompt is written to the agent, which is what lets recovery find it again. Stopping and
// retrying are in `HostCore+Stopping.swift`, the queue's edits in `HostCore+Queue.swift`, the
// agent's requests (permissions, questions) in `HostCore+Agents.swift`.
extension HostCore {
    /// Delivers a message: as a new turn when the session is idle, otherwise steered into the running
    /// turn or queued. A request id seen before gets the same answer and is never delivered twice,
    /// including a repeat that arrives while the first is still being handled.
    func prompt(
        _ params: PromptParams, checking authorization: (@HostActor @Sendable () throws -> Void)? = nil
    ) async throws -> PromptDelivery {
        // In flight first: a steer records itself as queued before the agent answers.
        if let inFlight = promptsInFlight[params.requestID] {
            return try await inFlight.value
        }
        if let delivery = try store.delivery(for: params.requestID) {
            return delivery
        }
        let task = Task {
            try authorization?()
            return try await deliver(params)
        }
        promptsInFlight[params.requestID] = task
        defer { promptsInFlight[params.requestID] = nil }
        return try await task.value
    }

    private func deliver(_ params: PromptParams) async throws -> PromptDelivery {
        let session = try session(params.sessionID)
        guard session.record.origin != .announced else { throw HostError.notAcceptingPrompts }
        let text = PromptQuote.trimmed(params.text)
        guard !text.isEmpty || params.content?.isEmpty == false || !params.attachments.isEmpty else {
            throw HostError.emptyMessage
        }
        let item = OutgoingPrompt(
            id: params.requestID, text: text, content: params.content, attachments: params.attachments,
            preamble: params.preamble, isEchoed: params.echo, origin: params.origin)
        switch session.phase {
        case .idle where session.turn == nil && session.hiddenCommand == nil:
            cancelRetry(of: session)
            // The user sending again lifts a pause after a stopped turn; waiting messages go first.
            if !session.queue.isEmpty {
                try enqueue(item, in: session)
                session.record.isQueuePaused = false
                try store.updateSession(session.record)
                drainQueue(session)
                publish(session)
                return .queued
            }
            try startTurn(in: session, prompt: item)
            return .prompted
        case .prompting where params.behavior == .steer && !session.isStopping:
            return try await submitSteer(item, into: session)
        default:
            // Sending during reattachment is the same explicit resume as sending while idle.
            if (session.phase == .loading || session.phase == .disconnected) && session.preservesTranscriptOnLoad {
                session.record.isQueuePaused = false
                try store.updateSession(session.record)
            }
            try enqueue(item, in: session)
            if session.phase == .disconnected {
                // A message for a session whose agent couldn't run is a cue to try again.
                Task { try? await load(session) }
            }
            return .queued
        }
    }

    func enqueue(_ item: OutgoingPrompt, in session: HostSession, atFront: Bool = false, steering: Bool = false) throws
    {
        let stored = StoredQueueItem(prompt: item, isSteering: steering)
        if atFront {
            session.queue.insert(stored, at: 0)
        } else if item.steersAfterTools {
            let index = session.queue.firstIndex(where: { !$0.prompt.steersAfterTools && !$0.isSteering })
            session.queue.insert(stored, at: index ?? session.queue.endIndex)
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
    /// Any turn starting lifts a pause on the queue.
    func startTurn(
        in session: HostSession, prompt: OutgoingPrompt, kind: UnfinishedTurn.Kind = .prompt, attempts: Int = 0
    ) throws {
        let turn = UnfinishedTurn(sessionID: session.id, prompt: prompt, kind: kind, attempts: attempts)
        session.record.lastActivity = .now
        session.record.isQueuePaused = false
        try store.transaction {
            try store.beginTurn(turn)
            try store.recordDelivery(.prompted, for: prompt.id, in: session.id)
            try store.setQueue(session.queue, for: session.id)
            try store.updateSession(session.record)
        }
        session.steeringGate.reset()
        session.turn = turn
        session.stopAcknowledged = false
        session.phase = .prompting
        session.hiddenCommandEcho = nil
        // Instructions go ahead of the message unless the agent already has these.
        let preamble = prompt.preamble.flatMap {
            session.mirror.state.deliveredPreamble?.id == $0.marker.id ? nil : $0
        }
        let echo = PromptEcho(
            text: prompt.text, origin: prompt.origin, requestID: prompt.origin == .recovery ? nil : prompt.id,
            shown: prompt.isEchoed, attachments: prompt.attachments, preamble: preamble?.marker)
        session.turnEcho = (echo, .now)
        append(.prompt(echo), to: session)
        session.turnItemsStart = session.mirror.state.items.count
        titleAfterPrompt(session, prompt: prompt, kind: kind)
        publish(session)
        let blocks = (preamble.map { [$0.preamble.block] } ?? []) + (prompt.content ?? [.text(prompt.text)])
        Task { await run(turn, blocks: blocks, in: session) }
    }

    /// Shows the running turn's message again at the end of a load's replay, which started the
    /// transcript over from the agent's history: the turn waits for the load, so the agent hasn't
    /// seen the message yet. Inside the load, as it was sent, so clients take it for the same turn.
    func showPendingMessage(of session: HostSession) {
        guard session.turn != nil, let (echo, sentAt) = session.turnEcho else { return }
        append(.prompt(echo), to: session, at: sentAt)
        session.turnItemsStart = session.mirror.state.items.count
    }

    private func run(_ turn: UnfinishedTurn, blocks: [ContentBlock], in session: HostSession) async {
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
        // Naming suspends this run just like the prompt does. Neither continuation owns work on
        // a replacement connection, even when recovery reuses the same durable request id.
        func ownsTurn() -> Bool {
            sessions[session.id] === session && session.turn?.requestID == turn.requestID
                && agents[session.record.agentID] === link && link.generation == generation && link.peer === peer
        }
        do {
            if session.stopRequestedAt != nil {
                finish(turn, in: session, stopReason: "cancelled")
                return
            }
            let namingStopReason = try await nameInAgent(session, beforeSending: turn.prompt, on: link, peer: peer)
            guard ownsTurn() else { return }
            if namingStopReason == "cancelled" || session.stopRequestedAt != nil {
                finish(turn, in: session, stopReason: "cancelled")
                return
            }
            let response = try await peer.request(
                "session/prompt", PromptRequest(sessionId: agentSessionID, prompt: blocks), as: RawPromptResponse.self)
            guard ownsTurn() else { return }
            finish(turn, in: session, stopReason: response.stopReason)
        } catch PeerError.closed {
            // The agent died mid-turn; recovery takes it from here.
            guard ownsTurn() else { return }
            agentExited(session.record.agentID, generation: generation)
        } catch {
            guard ownsTurn() else { return }
            noteAgentError(error, from: link)
            fail(turn, in: session, error: error)
        }
    }

    func finish(_ turn: UnfinishedTurn, in session: HostSession, stopReason: String) {
        guard session.turn?.requestID == turn.requestID else { return }
        guard !session.isStopping else {
            session.stopAcknowledged = true
            return
        }
        // Queued messages wait out a stopped turn until the user sends again.
        let pause = stopReason == "cancelled" && session.steeringInterruptTurn != turn.requestID
        endTurn(in: session, stopReason: stopReason, pauseQueue: pause)
        session.retryAttempts = 0
        append(.turnEnded(stopReason: stopReason), to: session)
        if stopReason == "end_turn", session.record.parentID == nil {
            journal(.turnFinished, session: session)
        }
        publish(session)
        continueAfterTurn(session)
    }

    /// The prompt request failed. A passing failure (the network, an overloaded provider) before the
    /// agent got anywhere sends the message again a little later; anything else waits for the user.
    private func fail(_ turn: UnfinishedTurn, in session: HostSession, error: any Error) {
        guard session.turn?.requestID == turn.requestID else { return }
        guard !session.isStopping else { return }
        let madeProgress = session.turnMadeProgress
        // An error isn't a stop reason; draining the queue after one could burn through all of it.
        endTurn(in: session, stopReason: "error", pauseQueue: true)
        let message: String
        var retry: DeliveryRetry?
        if !madeProgress, turn.kind == .prompt,
            let delay = TurnRetry.delay(after: error, attempts: session.retryAttempts)
        {
            session.retryAttempts += 1
            // Already in the transcript, so it goes back without showing again.
            var again = turn.prompt
            again.isEchoed = false
            try? enqueue(again, in: session, atFront: true)
            scheduleRetry(of: session, after: delay)
            let details = DeliveryRetry(
                agentName: session.agentName, reason: error.localizedDescription, delay: Int(delay.components.seconds))
            retry = details
            message = details.waitingText
        } else {
            message = UsageLimitHit(error: error).map(\.message) ?? error.localizedDescription
            journal(.turnFailed, session: session, detail: message)
        }
        // The summary first: whoever hears of the failure can tell whether a retry is coming.
        publish(session)
        append(.turnFailed(message: message, error: error as? RPCError, retry: retry), to: session)
        exitIfIdleForRestart()
    }

    func endTurn(in session: HostSession, stopReason: String, pauseQueue: Bool) {
        if let turn = session.turn, turn.kind == .prompt {
            titleAfterFirstTurn(session, promptID: turn.prompt.id, succeeded: stopReason == "end_turn")
        }
        session.steeringGate.reset()
        session.steeringInterruptTurn = nil
        session.turn = nil
        session.phase = .idle
        session.record.lastStopReason = stopReason
        session.record.isQueuePaused = pauseQueue
        session.stopRequestedAt = nil
        session.stopTimeout?.cancel()
        session.stopTimeout = nil
        withdrawPermissions(of: session)
        withdrawQuestions(of: session)
        try? store.transaction {
            try store.finishTurn(session.id)
            try store.updateSession(session.record)
        }
    }

    /// What follows a turn's end: the message the user sent while stopping goes first (even though
    /// stopping pauses the queue), otherwise the queue, unless it's paused.
    func continueAfterTurn(_ session: HostSession) {
        guard !isStoppingAllAgents, !isRestartingImmediately else { return }
        if let id = session.sendAfterStop {
            session.sendAfterStop = nil
            if let index = session.queue.firstIndex(where: { $0.prompt.id == id }) {
                let item = session.queue.remove(at: index)
                try? startTurn(in: session, prompt: item.prompt)
                return
            }
        }
        drainQueue(session)
        exitIfIdleForRestart()
    }

    /// Starts the next queued message once nothing is running, one per turn, unless paused.
    func drainQueue(_ session: HostSession) {
        guard session.phase == .idle, session.turn == nil, session.hiddenCommand == nil, session.retryAt == nil,
            !session.record.isQueuePaused,
            let index = session.queue.firstIndex(where: { $0.prompt.steersAfterTools && !$0.isSteering })
                ?? session.queue.firstIndex(where: { !$0.isSteering })
        else { return }
        let next = session.queue.remove(at: index)
        var prompt = next.prompt
        prompt.steersAfterTools = false
        if prompt.origin == .user {
            prompt.origin = .queued
        }
        do {
            try startTurn(in: session, prompt: prompt)
        } catch {
            session.queue.insert(next, at: index)
            logger.error("Couldn't start a queued turn: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings and hidden commands

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
            // As the agent took it (setting the model can move the effort too), so a reload that
            // comes back on other values gets these set back.
            pinConfig(Self.configOptions(options), of: session)
        } else {
            // The agent didn't say what it's on: as asked.
            session.record.configChoices[params.configID] = params.value
            try? store.updateSession(session.record)
        }
    }

    /// Runs a command such as `/context` as a turn the transcript doesn't show, and returns the
    /// agent's reply. Meanwhile the session looks idle, but messages queue. Not a durable turn: if
    /// the host stops, it's simply gone.
    func runHidden(_ params: RunHiddenParams) async throws -> String {
        let session = try session(params.sessionID)
        guard session.record.origin != .announced else { throw HostError.notAcceptingPrompts }
        try await load(session)
        guard session.phase == .idle, session.turn == nil, session.hiddenCommand == nil else {
            throw HostError.busy("The task is busy.")
        }
        guard let peer = agents[session.record.agentID]?.peer, let agentSessionID = session.record.agentSessionID else {
            throw HostError.agentUnavailable(session.agentName)
        }
        session.hiddenCommand = HiddenCommandCapture()
        publish(session)
        defer {
            session.hiddenCommandEcho = session.hiddenCommand
            session.hiddenCommand = nil
            publish(session)
            drainQueue(session)
        }
        _ = try await peer.request(
            "session/prompt", PromptRequest(sessionId: agentSessionID, prompt: [.text(params.text)]),
            as: RawPromptResponse.self)
        return session.hiddenCommand?.output ?? ""
    }
}
