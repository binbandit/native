import ACP
import Foundation

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
        case loading
        case disconnected
        case busy

        var errorDescription: String? {
            switch self {
            case .emptyMessage: "There's nothing to send."
            case .notAcceptingPrompts: "This subagent only takes work from the session that started it."
            case .loading: "The session is still loading."
            case .disconnected: "The session's agent stopped running."
            case .busy: "The session is busy."
            }
        }
    }

    /// Messages waiting for the running turn to end, in the order they'll go out. Messages that
    /// don't show in the transcript (`echo: false`) aren't listed.
    var queuedPrompts: [QueuedPrompt] {
        queue.items.filter(\.isEchoed)
    }

    /// Sends the user's draft as a prompt, if the agent is idle, and waits for the turn to end.
    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard origin == .user, phase == .idle, !isRunningHiddenCommand, !text.isEmpty else { return }
        draft = ""
        let start = beginTurn(text, echo: true)
        await finishTurn(text, itemsStart: start)
    }

    /// Sends the user's draft whatever the agent is doing: right away when it's idle, otherwise
    /// queued for when the turn ends or steered into the running turn, as `behavior` says.
    func submit(_ behavior: FollowUpBehavior) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard origin == .user, phase == .idle || phase == .prompting, !text.isEmpty else { return }
        draft = ""
        if phase == .idle, !isRunningHiddenCommand {
            // The user sending again lifts a pause after a cancelled turn. Waiting messages go first.
            queue.resume()
            queue.append(text)
            drainQueue()
        } else {
            _ = try? await submit(text, behavior)
        }
    }

    /// Sends `text` on someone's behalf (another session, a workflow, a timer) whatever the agent is
    /// doing, leaving the draft alone. When idle, it returns once the turn has started, not when it
    /// ends. While a turn runs it steers (if `behavior` asks and the agent can) or queues. `echo:
    /// false` keeps the text out of the transcript, now and when it goes out from the queue.
    @discardableResult
    func submit(_ text: String, _ behavior: FollowUpBehavior, echo: Bool = true) async throws -> FollowUpDelivery {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SendError.emptyMessage }
        guard acceptsPrompts else { throw SendError.notAcceptingPrompts }
        switch phase {
        case .loading:
            throw SendError.loading
        case .disconnected:
            throw SendError.disconnected
        case .idle where !isRunningHiddenCommand:
            startTurn(text, echo: echo)
            return .prompted
        case .prompting where behavior == .steer && supportsSteering:
            return await steer(text, echo: echo)
        case .idle, .prompting:
            queue.append(text, isEchoed: echo)
            return .queued
        }
    }

    /// Edits a queued message; emptying it removes it.
    func updateQueued(_ id: QueuedPrompt.ID, text: String) {
        queue.update(id, text: text)
    }

    /// Removes a queued message; with an undo manager, ⌘Z puts it back in its place.
    func removeQueued(_ id: QueuedPrompt.ID, undoManager: UndoManager? = nil) {
        guard let index = queue.index(of: id), let item = queue.remove(id) else { return }
        undoManager?.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated {
                session.queue.restore(item, at: index)
            }
        }
        undoManager?.setActionName("Delete Queued Message")
    }

    /// Sends a queued message now instead of waiting: into the running turn, or as the next prompt
    /// when the agent is idle (as it is after a cancelled turn paused the queue).
    func steerQueued(_ id: QueuedPrompt.ID) async {
        if phase == .prompting, supportsSteering, let item = queue.remove(id) {
            await steer(item.text, echo: item.isEchoed)
        } else if phase == .idle, !isRunningHiddenCommand, let item = queue.remove(id) {
            queue.resume()
            startTurn(item.text, echo: item.isEchoed)
        }
    }

    /// Starts the next queued message once nothing is running, one per turn, unless the queue is
    /// paused.
    func drainQueue() {
        guard phase == .idle, !isRunningHiddenCommand, let next = queue.next() else { return }
        startTurn(next.text, echo: next.isEchoed)
    }

    // MARK: - Running a turn

    /// Starts a turn and runs it in the background, so the session is prompting by the time this
    /// returns.
    private func startTurn(_ text: String, echo: Bool) {
        let start = beginTurn(text, echo: echo)
        Task { await finishTurn(text, itemsStart: start) }
    }

    /// Records the prompt and marks the turn as running, before anything suspends. Returns where the
    /// turn's own items begin in the transcript.
    private func beginTurn(_ text: String, echo: Bool) -> Int {
        let isFirstPrompt = !state.items.contains { item in
            if case .message(let message) = item { message.role == .user } else { false }
        }
        if echo {
            state.appendUserMessage(text)
        }
        phase = .prompting
        lastActivity = .now
        if isFirstPrompt {
            // Named alongside the turn rather than before it, so the prompt goes out right away.
            let request = TitleRequest(projectName: cwd.lastPathComponent, prompt: text)
            Task { await services.titles.generateIfNeeded(for: titleKey, request: request, using: services.plugins.titler) }
        }
        services.post(.promptSent(context, text: text))
        return state.items.count
    }

    private func finishTurn(_ text: String, itemsStart start: Int) async {
        do {
            let response = try await connection.send(PromptRequest(sessionId: id, prompt: [.text(text)]))
            state.endTurn(response.stopReason)
            lastStopReason = response.stopReason
            services.post(.turnEnded(context, response.stopReason))
        } catch {
            let items = Array(state.items[min(start, state.items.count)...])
            state.appendNotice(UsageLimitHit(error: error).map(\.message) ?? error.localizedDescription, isError: true)
            lastStopReason = .error
            services.post(.turnFailed(context, prompt: text, error: error, items: items))
        }
        // Set after the stop reason, so whoever watches the phase reads how the turn ended.
        if phase == .prompting {
            phase = .idle
        }
        // Queued messages wait out a cancelled or failed turn, until the user sends again.
        if lastStopReason == .cancelled || lastStopReason == .error {
            queue.pause()
        } else {
            drainQueue()
        }
    }

    /// Adds `text` to the running turn. If the turn ended first, it goes to the front of the queue.
    @discardableResult
    private func steer(_ text: String, echo: Bool) async -> FollowUpDelivery {
        var delivery = FollowUpDelivery.queued
        do {
            let response = try await connection.send(SteerRequest(sessionId: id, prompt: [.text(text)]))
            switch response.outcome {
            case .injected:
                if echo { state.appendUserMessage(text, steered: true) }
                delivery = .steered
            case .startedNewTurn:
                // An older agent took it as a new prompt of its own; it's been delivered.
                if echo { state.appendUserMessage(text) }
                delivery = .steered
            case .promptRequired, .other:
                queue.prepend(text, isEchoed: echo)
            }
        } catch {
            queue.append(text, isEchoed: echo)
            state.appendNotice("Couldn't add your message to the running turn, so it's queued: \(error.localizedDescription)", isError: true)
        }
        // The turn may have ended while the steer was in flight, leaving nothing to send the queue.
        drainQueue()
        return delivery
    }
}
