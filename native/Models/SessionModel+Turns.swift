import ACP
import AIInstructions
import Foundation
import NativeHostProtocol

// Turns: prompting, and what happens to messages sent while a turn runs (queued for when it ends,
// or steered into it).
extension SessionModel {
    /// What became of a message sent with `submit(_:_:echo:)`.
    nonisolated enum FollowUpDelivery: String, Sendable {
        /// It started a turn of its own.
        case prompted
        /// It joined the turn that was running.
        case steered
        /// It waits for the running turn to end.
        case queued
    }

    enum SendError: LocalizedError {
        case emptyMessage
        /// An agent's own subagent, which only its parent can give work to.
        case notAcceptingPrompts
        /// A conversation `/clear` set aside.
        case earlierConversation
        case loading
        case disconnected
        case busy

        var errorDescription: String? {
            switch self {
            case .emptyMessage: "There's nothing to send."
            case .notAcceptingPrompts: "This subagent only takes work from the task that started it."
            case .earlierConversation: SessionSendBlock.earlierConversation.message
            case .loading: "The task is still loading."
            case .disconnected: "The task's agent stopped running."
            case .busy: "The task is busy."
            }
        }
    }

    /// Messages waiting for the running turn to end, in the order they'll go out. Messages that
    /// don't show in the transcript (`echo: false`) aren't listed.
    var queuedPrompts: [QueuedPrompt] {
        host == nil ? queue.visible : hostQueuedPrompts
    }

    /// Whether any message waits to go out, shown or not.
    var hasQueuedPrompts: Bool {
        guard host != nil else { return !queue.isEmpty }
        return hostSummary?.queue.isEmpty == false || !heldPrompts.isEmpty
    }

    /// Sends the user's draft as a prompt, if the agent is idle, and waits for the turn to end.
    func send() async {
        let text = PromptQuote.trimmed(draft)
        let attachments = self.attachments
        guard origin == .user, acceptsPrompts, phase == .idle, !isRunningHiddenCommand, turnHold == nil,
            !text.isEmpty || !attachments.isEmpty
        else {
            return
        }
        hasSubmittedPrompt = true
        draft = ""
        self.attachments = []
        if host != nil {
            guard (try? await submitToHost(text, attachments: attachments, behavior: .queue, echo: true)) == .prompted
            else { return }
            for await phase in Observations({ self.phase }) where phase != .prompting {
                break
            }
            return
        }
        let turn = beginTurn(text, attachments: attachments, echo: true)
        await finishTurn(
            text, attachments: attachments, preamble: turn.preamble, itemsStart: turn.itemsStart,
            generation: turnGeneration)
    }

    /// Sends the user's draft whatever the agent is doing: right away when it's idle, otherwise
    /// queued for when the turn ends or steered into the running turn, as `behavior` says.
    func submit(_ behavior: FollowUpBehavior) async {
        let text = PromptQuote.trimmed(draft)
        let attachments = self.attachments
        guard origin == .user, acceptsPrompts, phase == .idle || phase == .prompting,
            !text.isEmpty || !attachments.isEmpty
        else {
            return
        }
        hasSubmittedPrompt = true
        draft = ""
        self.attachments = []
        if host != nil {
            _ = try? await submitToHost(text, attachments: attachments, behavior: behavior, echo: true)
            return
        }
        if phase == .idle, !isRunningHiddenCommand, turnHold == nil {
            // The user sending again lifts a pause after a cancelled turn. Waiting messages go first.
            queue.resume()
            queue.append(text, attachments: attachments)
            drainQueue()
        } else {
            _ = try? await submit(text, attaching: attachments, behavior)
        }
    }

    /// Sends `text` on someone's behalf (another session, a workflow, a timer) whatever the agent is
    /// doing, leaving the draft alone. When idle, it returns once the turn has started, not when it
    /// ends. While a turn runs it steers (if `behavior` asks and the agent can) or queues, as it
    /// does while the session loads. `echo: false` keeps the text out of the transcript, now and
    /// when it goes out from the queue. `attachments` (files, images) go with the text as their own
    /// content blocks.
    @discardableResult
    func submit(
        _ text: String, attaching attachments: [PromptAttachment] = [], _ behavior: FollowUpBehavior, echo: Bool = true
    ) async throws -> FollowUpDelivery {
        let text = PromptQuote.trimmed(text)
        guard !text.isEmpty || !attachments.isEmpty else { throw SendError.emptyMessage }
        guard !isChangingAgent, !isChangingWorkspace, !isWorkspaceReplaced else { throw SendError.busy }
        guard acceptsPrompts else {
            throw isEarlierConversation ? SendError.earlierConversation : .notAcceptingPrompts
        }
        hasSubmittedPrompt = true
        if host != nil {
            // The host takes messages whatever the session is doing: one for a session whose agent
            // couldn't start is its cue to try again.
            return try await submitToHost(text, attachments: attachments, behavior: behavior, echo: echo)
        }
        switch phase {
        case .loading:
            // Sent the moment the session has loaded (`finishLoading`), rather than refused.
            queue.append(text, attachments: attachments, isEchoed: echo)
            return .queued
        case .disconnected:
            throw SendError.disconnected
        case .idle where !isRunningHiddenCommand && turnHold == nil:
            startTurn(text, attachments: attachments, echo: echo)
            return .prompted
        case .prompting where behavior == .steer && supportsSteering && !isStopping:
            return await steer(text, attachments: attachments, echo: echo)
        case .idle, .prompting:
            queue.append(text, attachments: attachments, isEchoed: echo)
            return .queued
        }
    }

    /// Edits a queued message; emptying one that carries no files removes it.
    func updateQueued(_ id: QueuedPrompt.ID, text: String) {
        guard host == nil else { return updateQueuedOnHost(id, text: text) }
        queue.update(id, text: text)
    }

    /// Removes a queued message; with an undo manager, ⌘Z puts it back in its place.
    func removeQueued(_ id: QueuedPrompt.ID, undoManager: UndoManager? = nil) {
        guard host == nil else { return removeQueuedOnHost(id, undoManager: undoManager) }
        guard let index = queue.index(of: id), let item = queue.remove(id) else { return }
        undoManager?.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated {
                session.queue.restore(item, at: index)
            }
        }
        undoManager?.setActionName("Delete Queued Message")
    }

    /// How "Send Now" delivers a queued message right now, if it can.
    enum SendNowRoute: Equatable {
        /// Into the running turn.
        case steer
        /// The running turn stops, then the message goes as the next prompt.
        case interrupt
        /// As the next prompt, while the agent is idle (as it is after a stopped turn).
        case send
    }

    var sendNowRoute: SendNowRoute? {
        switch phase {
        case .prompting: supportsSteering ? .steer : .interrupt
        case .idle where !isRunningHiddenCommand && turnHold == nil: .send
        case .idle, .loading, .disconnected: nil
        }
    }

    /// Sends a queued message now instead of waiting, as `sendNowRoute` says. Like any new turn, it
    /// lifts the pause a stopped turn put on the rest.
    func sendQueuedNow(_ id: QueuedPrompt.ID) async {
        if host != nil {
            if editingQueuedPrompt == id {
                editingQueuedPrompt = nil
            }
            return await sendQueuedNowOnHost(id)
        }
        guard queue.index(of: id) != nil else { return }
        if editingQueuedPrompt == id {
            editingQueuedPrompt = nil
        }
        switch sendNowRoute {
        case .steer:
            guard let item = queue.remove(id) else { return }
            await steer(item.text, attachments: item.attachments, echo: item.isEchoed)
        case .interrupt:
            sendAfterStop = id
            await cancel()
        case .send:
            guard let item = queue.remove(id) else { return }
            startTurn(item.text, attachments: item.attachments, echo: item.isEchoed)
        case nil:
            break
        }
    }

    func canMoveQueued(_ id: QueuedPrompt.ID, _ direction: PromptQueue.Direction) -> Bool {
        guard host != nil else { return queue.canMove(id, direction) }
        let visible = queuedPrompts
        guard let position = visible.firstIndex(where: { $0.id == id }) else { return false }
        return direction == .up ? position > 0 : position < visible.count - 1
    }

    /// Moves a queued message one place sooner or later.
    func moveQueued(_ id: QueuedPrompt.ID, _ direction: PromptQueue.Direction) {
        guard host != nil else { return queue.move(id, direction) }
        let visible = queuedPrompts
        guard canMoveQueued(id, direction), let position = visible.firstIndex(where: { $0.id == id }) else { return }
        let target = direction == .up ? visible[position - 1].id : visible.dropFirst(position + 2).first?.id
        moveQueuedOnHost(id, before: target)
    }

    /// Moves a queued message to just before `target`, or to the end: where a drag dropped it.
    func moveQueued(_ id: QueuedPrompt.ID, before target: QueuedPrompt.ID?) {
        guard host == nil else { return moveQueuedOnHost(id, before: target) }
        queue.move(id, before: target)
    }

    /// Starts the next queued message once nothing is running, one per turn, unless the queue is
    /// paused.
    func drainQueue() {
        guard host == nil else { return sendHeldPrompts() }
        guard phase == .idle, !isRunningHiddenCommand, turnHold == nil, let next = queue.next() else { return }
        startTurn(next.text, attachments: next.attachments, echo: next.isEchoed)
    }

    // MARK: - Running a turn

    /// Starts a turn and runs it in the background, so the session is prompting by the time this
    /// returns.
    private func startTurn(_ text: String, attachments: [PromptAttachment], echo: Bool) {
        let turn = beginTurn(text, attachments: attachments, echo: echo)
        let generation = turnGeneration
        Task {
            await finishTurn(
                text, attachments: attachments, preamble: turn.preamble, itemsStart: turn.itemsStart,
                generation: generation)
        }
    }

    /// Records the prompt and marks the turn as running, before anything suspends. Returns where the
    /// turn's own items begin in the transcript, and the instructions that go ahead of the prompt.
    private func beginTurn(
        _ text: String, attachments: [PromptAttachment], echo: Bool
    ) -> (itemsStart: Int, preamble: PromptPreamble?) {
        cancelRetry()
        // A new turn puts a stopped one behind it: what's queued now goes out as this one ends.
        queue.resume()
        hiddenCommandEcho = nil
        let isFirstPrompt = !state.items.contains { item in
            if case .message(let message) = item { message.role == .user } else { false }
        }
        // A mode's instructions, say, which the transcript shows as a marker (`SessionHooks`).
        let preamble = services.hooks.preamble(for: self, prompt: text)
        if echo {
            let startedAt = Date.now
            state.appendUserMessage(
                text, attachments: MessageAttachment.shown(attachments, capabilities: promptCapabilities),
                preamble: preamble?.marker, at: startedAt)
            services.hooks.turnStarted(self, startedAt)
        }
        phase = .prompting
        lastActivity = .now
        // Automatic delivery retries are already in the transcript. They must not spend the
        // title retry reserved for the next message the user sends.
        nameAfterPrompt(text, attachments: attachments, isFirstPrompt: isFirstPrompt, allowsRetry: echo)
        services.post(.promptSent(context, text: text))
        return (state.items.count, preamble)
    }

    /// Starts or retries the title alongside a turn, so the prompt goes out right away.
    func nameAfterPrompt(
        _ text: String, attachments: [PromptAttachment], isFirstPrompt: Bool, allowsRetry: Bool = true
    ) {
        let prompt = text.isEmpty ? attachments.map(\.name).joined(separator: ", ") : text
        let request = TitleRequest(
            projectName: cwd.lastPathComponent, prompt: prompt,
            instructions: AIInstructionsStore.shared.addition(for: .title, in: cwd))
        Task {
            let previous = services.titles.namedTitle(for: titleKey)
            await services.titles.generateIfNeeded(
                for: titleKey, request: request, using: services.plugins.titler, isFirstPrompt: isFirstPrompt,
                allowsRetry: allowsRetry)
            if let title = services.titles.namedTitle(for: titleKey), isFirstPrompt || title != previous {
                services.titleLanded(key, cwd, title)
            }
        }
    }

    /// Waits for the turn's answer and records how it ended. `generation` is the turn's
    /// `turnGeneration`: an answer for an older turn changes nothing.
    private func finishTurn(
        _ text: String, attachments: [PromptAttachment], preamble: PromptPreamble?, itemsStart start: Int,
        generation: Int
    ) async {
        do {
            let prompt = (preamble.map { [$0.block] } ?? []) + promptBlocks(text, attachments: attachments)
            guard let connection else { throw SendError.disconnected }
            let response = try await connection.send(PromptRequest(sessionId: id, prompt: prompt))
            guard generation == turnGeneration else { return }
            guard !isStopping else { return }
            state.endTurn(response.stopReason)
            lastStopReason = response.stopReason
            services.post(.turnEnded(context, response.stopReason))
        } catch {
            guard generation == turnGeneration else { return }
            guard !isStopping else { return }
            let items = Array(state.items[min(start, state.items.count)...])
            let madeProgress = items.contains { item in
                switch item {
                case .message(let message): message.role != .user
                case .toolCall, .subagent: true
                default: false
                }
            }
            if let delay = retryPolicy.nextDelay(after: error, turnMadeProgress: madeProgress) {
                // Already in the transcript, so it goes back without showing again.
                queue.prepend(text, attachments: attachments, isEchoed: false)
                scheduleRetry(after: delay)
                state.appendNotice(
                    "\(agentName) couldn't be reached (\(error.localizedDescription.withoutTerminalEscapes)). "
                        + "Native kept your message and will try again in \(delay.components.seconds) seconds. "
                        + "Use Stop to cancel.",
                    isError: true)
            } else {
                // Agents pass their terminal-colored logs along in error messages.
                let message = UsageLimitHit(error: error).map(\.message) ?? error.localizedDescription
                state.appendNotice(message.withoutTerminalEscapes, isError: true)
            }
            // Closes the turn's clocks. The notice above already says what went wrong.
            state.endTurn(.error)
            lastStopReason = .error
            services.post(.turnFailed(context, prompt: text, error: error, items: items))
        }
        if lastStopReason != .error {
            retryPolicy.reset()
        }
        // Set after the stop reason, so whoever watches the phase reads how the turn ended.
        if phase == .prompting {
            phase = .idle
        }
        turnDidEnd()
    }

    /// What follows the end of a turn: the stop is over, and the next queued message goes out. A
    /// message the user sent while stopping goes first; otherwise queued messages wait out a
    /// cancelled or failed turn, until the user sends again.
    func turnDidEnd() {
        turnGeneration += 1
        finishStopping()
        if let id = sendAfterStop {
            sendAfterStop = nil
            if phase == .idle, let item = queue.remove(id) {
                startTurn(item.text, attachments: item.attachments, echo: item.isEchoed)
                return
            }
        }
        if lastStopReason == .cancelled || lastStopReason == .error {
            queue.pause()
        } else {
            drainQueue()
        }
    }

    /// The prompt as the agent takes it: the text, the attachments, and a link to each file the text
    /// mentions with `@`.
    func promptBlocks(_ text: String, attachments: [PromptAttachment]) -> [ContentBlock] {
        let mentions = PromptAttachment.mentions(in: text, relativeTo: cwd)
        modelChange?.closeUndo()
        let context = services.modelContinuations.take(for: key).map { [$0] } ?? []
        return context
            + ContentBlock.prompt(text, attachments: attachments + mentions, capabilities: promptCapabilities)
    }

    private func scheduleRetry(after delay: Duration) {
        isRetryScheduled = true
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            isRetryScheduled = false
            retryTask = nil
            queue.resume()
            drainQueue()
        }
    }

    func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        isRetryScheduled = false
    }

    /// Adds `text` to the running turn. If the turn ended first, it goes to the front of the queue.
    @discardableResult
    private func steer(_ text: String, attachments: [PromptAttachment], echo: Bool) async -> FollowUpDelivery {
        var delivery = FollowUpDelivery.queued
        do {
            let prompt = promptBlocks(text, attachments: attachments)
            guard let connection else { throw SendError.disconnected }
            let response = try await connection.send(SteerRequest(sessionId: id, prompt: prompt))
            switch response.outcome {
            case .injected:
                if echo {
                    state.appendUserMessage(
                        text, attachments: MessageAttachment.shown(attachments, capabilities: promptCapabilities),
                        steered: true)
                }
                delivery = .steered
            case .startedNewTurn:
                // An older agent took it as a new prompt of its own; it's been delivered.
                if echo {
                    state.appendUserMessage(
                        text, attachments: MessageAttachment.shown(attachments, capabilities: promptCapabilities))
                }
                delivery = .steered
            case .promptRequired, .other:
                queue.prepend(text, attachments: attachments, isEchoed: echo)
            }
        } catch {
            queue.append(text, attachments: attachments, isEchoed: echo)
            state.appendNotice(
                "Couldn't add your message to the running turn, so it's queued: \(error.localizedDescription)",
                isError: true)
        }
        // The turn may have ended while the steer was in flight, leaving nothing to send the queue.
        drainQueue()
        return delivery
    }
}
