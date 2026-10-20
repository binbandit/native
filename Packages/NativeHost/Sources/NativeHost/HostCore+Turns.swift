import ACP
import Foundation
import NativeHostProtocol

// Turns: prompting, steering, stopping, retrying after a passing failure, and hidden commands.
// Every turn is committed to the store before its prompt is written to the agent, which is what lets
// recovery find it again. The queue's edits are in `HostCore+Queue.swift`, the agent's requests
// (permissions, questions) in `HostCore+Agents.swift`.
extension HostCore {
    /// How long the agent gets to confirm a stop before the host stops waiting for it.
    static let stopGracePeriod: Duration = .seconds(10)

    /// Delivers a message: as a new turn when the session is idle, otherwise steered into the running
    /// turn or queued. A request id seen before gets the same answer and is never delivered twice,
    /// including a repeat that arrives while the first is still being handled.
    func prompt(_ params: PromptParams) async throws -> PromptDelivery {
        // In flight first: a steer records itself as queued before the agent answers.
        if let inFlight = promptsInFlight[params.requestID] {
            return try await inFlight.value
        }
        if let delivery = try store.delivery(for: params.requestID) {
            return delivery
        }
        let task = Task { try await deliver(params) }
        promptsInFlight[params.requestID] = task
        defer { promptsInFlight[params.requestID] = nil }
        return try await task.value
    }

    private func deliver(_ params: PromptParams) async throws -> PromptDelivery {
        let session = try session(params.sessionID)
        guard session.record.origin != .announced else { throw HostError.notAcceptingPrompts }
        let text = params.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func enqueue(_ item: OutgoingPrompt, in session: HostSession, atFront: Bool = false, steering: Bool = false) throws
    {
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
        session.turn = turn
        session.phase = .prompting
        session.hiddenCommandEcho = nil
        // Instructions go ahead of the message unless the agent already has these.
        let preamble = prompt.preamble.flatMap {
            session.mirror.state.deliveredPreamble?.id == $0.marker.id ? nil : $0
        }
        append(
            .prompt(
                PromptEcho(
                    text: prompt.text, origin: prompt.origin, requestID: prompt.origin == .recovery ? nil : prompt.id,
                    shown: prompt.isEchoed, attachments: prompt.attachments, preamble: preamble?.marker)),
            to: session)
        session.turnItemsStart = session.mirror.state.items.count
        publish(session)
        let blocks = (preamble.map { [$0.preamble.block] } ?? []) + (prompt.content ?? [.text(prompt.text)])
        Task { await run(turn, blocks: blocks, in: session) }
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
        do {
            let response = try await peer.request(
                "session/prompt", PromptRequest(sessionId: agentSessionID, prompt: blocks), as: RawPromptResponse.self)
            finish(turn, in: session, stopReason: response.stopReason)
        } catch PeerError.closed {
            // The agent died mid-turn; recovery takes it from here.
            agentExited(session.record.agentID, generation: generation)
        } catch {
            noteAgentError(error, from: link)
            fail(turn, in: session, error: error)
        }
    }

    func finish(_ turn: UnfinishedTurn, in session: HostSession, stopReason: String) {
        guard session.turn?.requestID == turn.requestID else { return }
        // Queued messages wait out a stopped turn until the user sends again.
        let pause = stopReason == "cancelled"
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
        let madeProgress = session.turnMadeProgress
        // An error isn't a stop reason; draining the queue after one could burn through all of it.
        endTurn(in: session, stopReason: "error", pauseQueue: true)
        let message: String
        if !madeProgress, turn.kind == .prompt,
            let delay = TurnRetry.delay(after: error, attempts: session.retryAttempts)
        {
            session.retryAttempts += 1
            // Already in the transcript, so it goes back without showing again.
            var again = turn.prompt
            again.isEchoed = false
            try? enqueue(again, in: session, atFront: true)
            scheduleRetry(of: session, after: delay)
            message =
                "\(session.agentName) couldn't be reached (\(error.localizedDescription)). Native kept your message and will try again in \(delay.components.seconds) seconds. Use Stop to cancel."
        } else {
            message = UsageLimitHit(error: error).map(\.message) ?? error.localizedDescription
            journal(.turnFailed, session: session, detail: message)
        }
        // The summary first: whoever hears of the failure can tell whether a retry is coming.
        publish(session)
        append(.turnFailed(message: message, error: error as? RPCError), to: session)
        exitIfIdleForRestart()
    }

    func endTurn(in session: HostSession, stopReason: String, pauseQueue: Bool) {
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
    private func continueAfterTurn(_ session: HostSession) {
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
            !session.record.isQueuePaused, let index = session.queue.firstIndex(where: { !$0.isSteering })
        else { return }
        let next = session.queue.remove(at: index)
        var prompt = next.prompt
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

    /// Adds a message to the running turn. It's recorded as steering first, so if the host stops
    /// before the agent answers, recovery can tell whether it arrived.
    func steer(_ item: OutgoingPrompt, into session: HostSession) async throws -> PromptDelivery {
        try enqueue(item, in: session, atFront: true, steering: true)
        var delivery = PromptDelivery.queued
        if let link = agents[session.record.agentID], let peer = link.peer,
            let agentSessionID = session.record.agentSessionID
        {
            do {
                let response = try await peer.request(
                    "_session/steering",
                    SteerRequest(sessionId: agentSessionID, prompt: item.content ?? [.text(item.text)]),
                    as: RawSteerResponse.self)
                switch response.outcome {
                case "injected", "startedNewTurn":
                    // An older agent takes it as a new turn of its own; either way it's delivered.
                    session.queue.removeAll { $0.prompt.id == item.id }
                    append(
                        .prompt(
                            PromptEcho(
                                text: item.text, steered: response.outcome == "injected", origin: item.origin,
                                requestID: item.id, shown: item.isEchoed, attachments: item.attachments)),
                        to: session)
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

    // MARK: - Stopping

    /// Stops what the session is doing: a retry waiting to go out, the running turn, or the recovery
    /// of one. The agent is asked to cancel; if it doesn't confirm within the grace period, or the
    /// user asks again more than a second later, the turn ends on the host's side.
    func cancel(_ session: HostSession) async {
        if session.retryAt != nil {
            cancelRetry(of: session)
            append(
                .notice(text: "Stopped retrying. Your message is still queued; send again to try it.", isError: false),
                to: session)
            publish(session)
            return
        }
        let link = agents[session.record.agentID]
        if session.record.origin == .announced, let peer = link?.peer,
            let agentSessionID = session.record.agentSessionID
        {
            // An agent's own subagent has no turn of its own; stopping it stops only its work.
            answerCancelled(session, on: peer)
            try? peer.notify("session/cancel", CancelNotification(sessionId: agentSessionID))
            publish(session)
            return
        }
        guard let turn = session.turn else { return }
        guard session.phase == .prompting, let peer = link?.peer, let agentSessionID = session.record.agentSessionID
        else {
            // Nothing is running to cancel (the agent is being restarted); just let the turn go.
            session.isRecoveryCancelled = true
            finish(turn, in: session, stopReason: "cancelled")
            return
        }
        if let first = session.stopRequestedAt {
            // A second press, not a double click, means the user is done waiting for the agent.
            if Date.now.timeIntervalSince(first) > 1 {
                abandon(turn, in: session)
            }
            return
        }
        session.stopRequestedAt = .now
        session.stopTimeout = Task { [weak self, weak session] in
            try? await Task.sleep(for: Self.stopGracePeriod)
            guard !Task.isCancelled, let self, let session else { return }
            abandon(turn, in: session)
        }
        answerCancelled(session, on: peer)
        try? peer.notify("session/cancel", CancelNotification(sessionId: agentSessionID))
        publish(session)
    }

    /// ACP requires answering open permission requests and questions as cancelled when a turn is
    /// cancelled.
    private func answerCancelled(_ session: HostSession, on peer: JSONRPCPeer) {
        for (_, requestID) in session.pendingPermissions {
            try? peer.respond(to: requestID, with: RequestPermissionResponse.cancelled)
        }
        withdrawPermissions(of: session)
        withdrawQuestions(of: session)
    }

    /// Ends a turn being stopped without the agent's word; its late answer is ignored.
    private func abandon(_ turn: UnfinishedTurn, in session: HostSession) {
        guard session.turn?.requestID == turn.requestID else { return }
        endTurn(in: session, stopReason: "cancelled", pauseQueue: true)
        append(.turnEnded(stopReason: "cancelled"), to: session)
        append(
            .notice(
                text:
                    "\(session.agentName) didn't confirm it stopped, so Native stopped waiting. It may still be finishing its last step.",
                isError: false), to: session)
        publish(session)
        continueAfterTurn(session)
    }

    // MARK: - Retrying

    private func scheduleRetry(of session: HostSession, after delay: Duration) {
        session.retryAt = .now.addingTimeInterval(Double(delay.components.seconds))
        session.retryTask = Task { [weak self, weak session] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let session else { return }
            session.retryAt = nil
            session.retryTask = nil
            session.record.isQueuePaused = false
            drainQueue(session)
            publish(session)
        }
    }

    func cancelRetry(of session: HostSession) {
        session.retryTask?.cancel()
        session.retryTask = nil
        session.retryAt = nil
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
        // Remembered so a reload that comes back on the agent's default gets it set back.
        session.record.configChoices[params.configID] = params.value
        try? store.updateSession(session.record)
        if let options = response.configOptions {
            append(.update(SessionMirror.configOptionsUpdate(options)), to: session)
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
            throw HostError.busy("The session is busy.")
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

/// When to send a failed prompt again: only when the failure looks like the network or the provider
/// being briefly unavailable, a few times, further apart each time. Usage limits and sign-in
/// problems are someone else's to handle.
enum TurnRetry {
    static let delays: [Duration] = [.seconds(5), .seconds(20), .seconds(60)]

    /// The wait before the next try, or nil to stop trying.
    static func delay(after error: any Error, attempts: Int) -> Duration? {
        guard isTransient(error), attempts < delays.count else { return nil }
        return delays[attempts]
    }

    static func isTransient(_ error: any Error) -> Bool {
        if (error as? RPCError)?.isAuthRequired == true || UsageLimitHit(error: error) != nil {
            return false
        }
        if error is URLError {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return transientMarkers.contains { text.contains($0) }
    }

    /// How agents word network and provider outages in the errors they pass on.
    private static let transientMarkers = [
        "network", "connection error", "connection refused", "connection reset", "timed out", "timeout",
        "econnreset", "econnrefused", "enotfound", "eai_again", "socket hang up", "fetch failed",
        "overloaded", "service unavailable", "bad gateway", "temporarily unavailable", " 502", " 503", " 529",
    ]
}
