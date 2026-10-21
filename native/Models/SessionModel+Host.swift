import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

/// Where a session runs in Native's host: the client that reaches the host and the session's id
/// there. Every action on a host session is one of its requests.
struct HostSessionLink {
    let client: NativeHostClient
    let id: HostSessionID

    /// Makes a request, waiting out a dropped connection once: a host that restarts is back within
    /// seconds, and the user's Stop or approval shouldn't be lost meanwhile.
    func request<Result: Sendable>(_ body: (NativeHostClient) async throws -> Result) async throws -> Result {
        do {
            return try await body(client)
        } catch let error where error is PeerError || error as? NativeHostClient.Failure == .notConnected {
            _ = try await client.connected()
            return try await body(client)
        }
    }

    func respondPermission(toolCallID: String, optionID: String?) async {
        let params = RespondPermissionParams(sessionID: id, toolCallID: toolCallID, optionID: optionID)
        try? await request { try await $0.respondPermission(params) }
    }

    func setConfigOption(_ configID: String, to value: String) async throws {
        let params = SetConfigOptionParams(sessionID: id, configID: configID, value: value)
        try await request { try await $0.setConfigOption(params) }
    }
}

/// A message a host session keeps until it can take it (`SessionModel.heldPrompts`).
struct HeldPrompt: Identifiable, Hashable {
    let id = UUID()
    var text: String
    let attachments: [PromptAttachment]
    let behavior: FollowUpBehavior
    let isEchoed: Bool
}

/// A turn the host reported as failed without an error of the agent's to pass on.
struct HostTurnFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

// A session in Native's host (docs/durability.md, Phase 2): the host runs its turns, queue,
// steering, stopping and retries, so they carry on with the app closed. This side mirrors the
// host's events into the transcript and turns the user's actions into host requests.
extension SessionModel {
    // MARK: - From the host

    /// The phase a host session shows. Setting a reloaded session's settings back counts as still
    /// loading, as it does in the app, unless the host has already started a turn.
    static func phase(of summary: HostSessionSummary, isSettingBackConfig: Bool) -> Phase {
        switch summary.phase {
        case .loading: .loading
        case .idle, .unknown: isSettingBackConfig ? .loading : .idle
        case .prompting, .recovering: .prompting
        case .disconnected: .disconnected
        }
    }

    /// Takes in what the host says about the session now.
    func apply(_ summary: HostSessionSummary) {
        hostSummary = summary
        let stopReason = summary.lastStopReason.map(SessionMirror.stopReason)
        if lastStopReason != stopReason { lastStopReason = stopReason }
        if lastActivity != summary.lastActivity { lastActivity = summary.lastActivity }
        if isStopping != summary.isStopping { isStopping = summary.isStopping }
        if isRetryScheduled != (summary.retryAt != nil) { isRetryScheduled = summary.retryAt != nil }
        if isRunningHiddenCommand != summary.isRunningHiddenCommand {
            isRunningHiddenCommand = summary.isRunningHiddenCommand
        }
        // Set last, so whoever watches the phase reads how the turn ended.
        let phase = Self.phase(of: summary, isSettingBackConfig: isSettingBackConfig)
        if self.phase != phase { self.phase = phase }
        sendHeldPrompts()
    }

    /// Applies one of the host's events. History (what happened before this model followed the
    /// session, or what the agent replays while it loads) rebuilds the transcript without reaching
    /// plugins again.
    func receive(_ step: SessionMirror.Step) {
        let isLive = !isReplaying && !mirror.isLoading
        if let update = step.update, !mirror.isLoading {
            switch update {
            case .subagent(let subagent): subagentControls.apply(subagent)
            case .usage(let usage) where isLive: services.post(.usageUpdated(context, usage))
            case .configOptions(let options) where isLive: AgentSessionDefaults.remember(options, for: agent.id)
            default: break
            }
        }
        // The title the agent listed the session with outlasts a reload that doesn't name it.
        let title = mirror.state.title
        if case .reset = step.event.payload {
            subagentControls.reset()
            answeredQuestions = []
        }
        // History arrives thousands of events at a time; the transcript hears about it in batches.
        if mirror.isLoading || phase == .loading || isReplaying {
            mirror.apply(step)
            if mirror.state.title == nil { mirror.state.title = title }
            mirrorState()
            noteReplayed()
        } else {
            withMutation(keyPath: \.state) {
                mirror.apply(step)
                if mirror.state.title == nil { mirror.state.title = title }
            }
            mirrorState()
        }
        switch step.event.payload {
        case .loaded:
            setBackConfigAfterLoad()
        case .prompt(let prompt) where isLive && prompt.shown && !prompt.steered:
            // The host sends a turn's prompt as it shows it, so the turn's own work comes later.
            services.hooks.turnStarted(self, step.event.at)
        case .turnEnded(let raw) where isLive:
            let reason = SessionMirror.stopReason(raw)
            lastStopReason = reason
            services.post(.turnEnded(context, reason))
        case .turnFailed(let message, let error) where isLive:
            lastStopReason = .error
            let (prompt, items) = latestTurn
            services.post(
                .turnFailed(context, prompt: prompt, error: error ?? HostTurnFailure(message: message), items: items))
        case .permissionRequested where isLive:
            services.post(
                .permissionRequested(context, toolCall: step.permissionRequest?.toolCall.title ?? "Tool call"))
        case .questionAsked where isLive:
            if let question = step.question {
                services.post(.questionAsked(context, message: question.message))
            }
        default:
            break
        }
    }

    /// The questions the host has open, less those answered here whose answer hasn't come back yet.
    func mirrorHostQuestions() {
        let open = mirror.questions.filter { !answeredQuestions.contains($0.id) }
        guard open.map(\.id) != questions.map(\.hostID) else { return }
        questions = open.map { PendingQuestion(id: .string($0.id), request: $0.request) }
    }

    /// The latest turn's prompt and what it produced, for plugins hearing that it failed.
    private var latestTurn: (prompt: String, items: [TranscriptItem]) {
        let items = state.items
        guard
            let start = items.lastIndex(where: { item in
                if case .message(let message) = item { message.role == .user && !message.wasSteered } else { false }
            }), case .message(let message) = items[start]
        else { return ("", []) }
        return (message.text, Array(items[start...]))
    }

    /// After the host (re)loaded the session: the host set back the settings it ran with before it
    /// said so (`HostCore.pinConfig`), and it's the one record of them, so the choices remembered here
    /// follow what it reports rather than going back on top. Only the organization's policy still
    /// wins over them. Messages sent meanwhile wait until it's done.
    private func setBackConfigAfterLoad() {
        guard !isSettingBackConfig else { return }
        isSettingBackConfig = true
        if let hostSummary { apply(hostSummary) }
        Task {
            await PolicyPermissionModes.enforce(on: self)
            isSettingBackConfig = false
            services.titles.updateConfigChoices(for: titleKey) { $0.follow(state.configOptions) }
            if let hostSummary { apply(hostSummary) }
        }
    }

    // MARK: - Messages

    /// Whether a message sent now waits here instead of going to the host: the session is loading
    /// or getting its settings back, or a workspace hold lasts while it's idle, when the message
    /// would start a turn.
    var holdsPrompts: Bool {
        phase == .loading || (phase == .idle && turnHold != nil)
    }

    /// Sends `text`, or holds it here while the session can't take it yet.
    func submitToHost(
        _ text: String, attachments: [PromptAttachment], behavior: FollowUpBehavior, echo: Bool
    ) async throws -> FollowUpDelivery {
        if holdsPrompts {
            heldPrompts.append(HeldPrompt(text: text, attachments: attachments, behavior: behavior, isEchoed: echo))
            return .queued
        }
        return try await sendToHost(text, attachments: attachments, behavior: behavior, echo: echo)
    }

    /// Sends what was held, in order, once the session can take it.
    func sendHeldPrompts() {
        guard !heldPrompts.isEmpty, !holdsPrompts, host != nil else { return }
        let held = heldPrompts
        heldPrompts = []
        Task {
            for prompt in held {
                do {
                    try await sendToHost(
                        prompt.text, attachments: prompt.attachments, behavior: prompt.behavior,
                        echo: prompt.isEchoed)
                } catch {
                    addNotice(
                        "Couldn't send a message that was waiting: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    /// Sends a message through the host, which starts a turn with it, steers it into the running
    /// one or queues it. Its request id makes resending it after a dropped connection safe.
    @discardableResult
    private func sendToHost(
        _ text: String, attachments: [PromptAttachment], behavior: FollowUpBehavior, echo: Bool
    ) async throws -> FollowUpDelivery {
        guard let host else { throw SendError.disconnected }
        let isFirstPrompt = !hasStarted
        let params = PromptParams(
            sessionID: host.id, text: text, content: promptBlocks(text, attachments: attachments),
            attachments: MessageAttachment.shown(attachments, capabilities: promptCapabilities).map(
                EchoAttachment.init),
            preamble: services.hooks.preamble(for: self, prompt: text).map(PromptPreambleSpec.init),
            behavior: behavior == .steer ? .steer : .queue, echo: echo, origin: origin == .task ? .task : .user)
        services.post(.promptSent(context, text: text))
        if isFirstPrompt {
            nameAfterFirstPrompt(text, attachments: attachments)
        }
        return switch try await host.client.prompt(params) {
        case .prompted: .prompted
        case .steered: .steered
        case .queued, .unknown: .queued
        }
    }

    /// Stops the turn, or the retry the host has scheduled. Native's own approval cards never
    /// reached the agent, so they're answered here.
    func cancelOnHost() async {
        guard let host else { return }
        for (toolCallID, permission) in state.pendingPermissions where NativeApprovals.isNative(permission.requestID) {
            state.resolvePermission(toolCallID: toolCallID)
            NativeApprovals.answer(permission.requestID, with: nil)
        }
        let id = host.id
        try? await host.request { try await $0.cancel(id) }
    }

    // MARK: - The queue

    /// The host's queue as the composer lists it, then what's held here.
    var hostQueuedPrompts: [QueuedPrompt] {
        let queued = (hostSummary?.queue ?? []).filter(\.isEchoed).map { prompt in
            QueuedPrompt(
                id: prompt.id, prompt.text,
                attachments: prompt.attachments.map { attachment in
                    PromptAttachment(
                        url: attachment.url ?? URL(filePath: attachment.name), content: .reference, byteCount: nil)
                })
        }
        let held = heldPrompts.filter(\.isEchoed).map {
            QueuedPrompt(id: $0.id, $0.text, attachments: $0.attachments)
        }
        return queued + held
    }

    func updateQueuedOnHost(_ id: QueuedPrompt.ID, text: String) {
        if let index = heldPrompts.firstIndex(where: { $0.id == id }) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, heldPrompts[index].attachments.isEmpty {
                heldPrompts.remove(at: index)
            } else {
                heldPrompts[index].text = text
            }
            return
        }
        guard let host else { return }
        let params = QueueItemParams(sessionID: host.id, itemID: id, text: text)
        Task { try? await host.request { try await $0.updateQueued(params) } }
    }

    func removeQueuedOnHost(_ id: QueuedPrompt.ID, undoManager: UndoManager?) {
        if let index = heldPrompts.firstIndex(where: { $0.id == id }) {
            let item = heldPrompts.remove(at: index)
            undoManager?.registerUndo(withTarget: self) { session in
                MainActor.assumeIsolated {
                    session.heldPrompts.insert(item, at: min(index, session.heldPrompts.count))
                }
            }
            undoManager?.setActionName("Delete Queued Message")
            return
        }
        guard let host, let index = hostSummary?.queue.firstIndex(where: { $0.id == id }) else { return }
        let params = QueueItemParams(sessionID: host.id, itemID: id)
        Task { try? await host.request { try await $0.removeQueued(params) } }
        // The host keeps what was removed, so undo puts it back with everything it carried.
        undoManager?.registerUndo(withTarget: self) { _ in
            let params = RestoreQueuedParams(sessionID: host.id, itemID: id, index: index)
            Task { try? await host.request { try await $0.restoreQueued(params) } }
        }
        undoManager?.setActionName("Delete Queued Message")
    }

    /// Moves a queued message to just before `target`, or to the end.
    func moveQueuedOnHost(_ id: QueuedPrompt.ID, before target: QueuedPrompt.ID?) {
        guard id != target else { return }
        if let index = heldPrompts.firstIndex(where: { $0.id == id }) {
            let item = heldPrompts.remove(at: index)
            let destination =
                target.flatMap { target in heldPrompts.firstIndex { $0.id == target } } ?? heldPrompts.endIndex
            heldPrompts.insert(item, at: destination)
            return
        }
        guard let host else { return }
        // A message the host has can't move among the ones held here, which go out after it anyway.
        let before = hostSummary?.queue.contains { $0.id == target } == true ? target : nil
        let params = MoveQueuedParams(sessionID: host.id, itemID: id, before: before)
        Task { try? await host.request { try await $0.moveQueued(params) } }
    }

    func sendQueuedNowOnHost(_ id: QueuedPrompt.ID) async {
        if let index = heldPrompts.firstIndex(where: { $0.id == id }) {
            let item = heldPrompts.remove(at: index)
            _ = try? await sendToHost(item.text, attachments: item.attachments, behavior: .steer, echo: item.isEchoed)
            return
        }
        guard let host else { return }
        let params = QueueItemParams(sessionID: host.id, itemID: id)
        try? await host.request { try await $0.sendQueuedNow(params) }
    }

    // MARK: - Hidden commands and questions

    func runHiddenCommandOnHost(_ command: String) async throws -> String {
        guard let host else { throw SendError.disconnected }
        return try await host.client.runHidden(RunHiddenParams(sessionID: host.id, text: command))
    }

    func respondOnHost(to question: PendingQuestion, with response: CreateElicitationResponse) async throws {
        guard let host, let questionID = question.hostID else { return }
        answeredQuestions.insert(questionID)
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(response))
        let params = RespondQuestionParams(sessionID: host.id, questionID: questionID, response: json)
        try await host.request { try await $0.respondQuestion(params) }
    }
}

extension SessionModel.PendingQuestion {
    /// The id the host asked the question by.
    fileprivate var hostID: String? {
        if case .string(let id) = id { id } else { nil }
    }
}
