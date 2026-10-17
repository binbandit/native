import ACP
import Foundation
import Observation

/// One agent session: its transcript and settings, plus the user's actions on it. Turns (sending,
/// queueing, steering) live in `SessionModel+Turns.swift`, hidden commands in
/// `SessionModel+HiddenCommands.swift`.
///
/// Besides the user's own sessions there are task sessions Native's tools start (a session
/// delegating work, a workflow step), prompted by code rather than the user and never listed in the
/// sidebar. A session can hang off another as its subagent: a task session started for it, or one
/// its agent announced (the user can watch that one, answer its permission requests and maybe
/// cancel its work, but nothing can prompt it).
@Observable
final class SessionModel {
    enum Phase: Equatable {
        /// Replaying history from the agent.
        case loading
        case idle
        case prompting
        /// The agent process went away; this session can't continue until it's reopened.
        case disconnected
    }

    /// Who started the session.
    enum Origin: Equatable {
        case user
        /// Started by Native's tools, on any agent: for another session (orchestration) or for none
        /// (a workflow step).
        case task
        /// Announced by its agent as a subagent of another session on the same connection.
        case announced
    }

    typealias QueuedPrompt = PromptQueue.Item

    let agent: AgentDefinition
    let id: SessionID
    /// Native's own identity for the session, assigned before the agent creates it (see
    /// `SessionContext`).
    let clientID: UUID
    let cwd: URL
    let origin: Origin
    /// The session that started this one; `nil` for sessions the user started.
    let parentID: SessionID?
    /// Whether messages can join a turn that's running (`SteerRequest`).
    let supportsSteering: Bool
    var draft = ""
    /// Subagent sessions this one started, by their session id.
    private(set) var children: [SessionID: SessionModel] = [:]

    /// Asks the composer to take focus; the composer clears it once it has. A flag rather than a
    /// counter, so a request made while the composer is being created isn't lost.
    var wantsComposerFocus = false
    /// Set to ask the session's view to open the model picker; the view clears it.
    var isModelPickerRequested = false
    /// Set to ask the session's view to show or hide the subagent inspector; the view clears it.
    var isSubagentInspectorToggleRequested = false

    // Turn state. Internal only so the SessionModel+ extensions in other files can drive turns;
    // everything else changes it through the methods.
    var state = SessionState()
    var phase: Phase
    /// When the user last sent a prompt, for ordering the sidebar.
    var lastActivity: Date?
    /// How the latest turn ended: the agent's stop reason, or `.error` when the prompt request
    /// threw. Nil until a turn has ended.
    var lastStopReason: StopReason?
    var queue = PromptQueue()
    var retryPolicy = TurnRetryPolicy()
    /// Waiting to send a prompt again after the network or the provider let it down.
    var isRetryScheduled = false
    @ObservationIgnored var retryTask: Task<Void, Never>?
    /// Questions the agent is waiting on (`elicitation/create`), oldest first; see
    /// SessionModel+Questions.
    var questions: [PendingQuestion] = []
    /// While a hidden command runs: the session takes no new turn, but its phase stays idle.
    var isRunningHiddenCommand = false
    @ObservationIgnored var hiddenCommand: HiddenCommandCapture?
    let connection: ACPConnection
    let services: SessionServices

    @ObservationIgnored private weak var parent: SessionModel?
    private var subagentControls = SubagentControls()

    /// A session of `agent`, the user's or (`origin: .task`) one Native's tools started. A task's
    /// `parent` adopts it as a subagent.
    init(
        agent: AgentDefinition, id: SessionID, clientID: UUID = UUID(), cwd: URL, connection: ACPConnection,
        services: SessionServices, supportsSteering: Bool, phase: Phase, title: String? = nil,
        configOptions: [ConfigOption] = [], origin: Origin = .user, parent: SessionModel? = nil
    ) {
        self.agent = agent
        self.id = id
        self.clientID = clientID
        self.cwd = cwd
        self.connection = connection
        self.services = services
        self.supportsSteering = supportsSteering
        self.phase = phase
        self.origin = origin
        parentID = parent?.id
        self.parent = parent
        state.title = title
        state.configOptions = configOptions
        parent?.children[id] = self
    }

    private init(announced id: SessionID, by parent: SessionModel) {
        agent = parent.agent
        self.id = id
        clientID = UUID()
        cwd = parent.cwd
        connection = parent.connection
        services = parent.services
        supportsSteering = false
        phase = .idle
        origin = .announced
        parentID = parent.id
        self.parent = parent
    }

    var key: SessionKey {
        SessionKey(agent: agent.id, id: id)
    }

    var agentName: String {
        agent.displayName
    }

    /// The title to show: the user's, then one generated from the first prompt, then the agent's.
    /// An announced subagent goes by what its parent calls it.
    var displayTitle: String {
        if origin == .announced {
            return parent?.state.subagents.first { $0.id == id }?.title ?? state.title ?? "Subagent"
        }
        return services.titles.title(for: titleKey, agentTitle: state.title) ?? (origin == .task ? "Task" : "New Session")
    }

    /// This session as plugins see it.
    var context: SessionContext {
        SessionContext(clientID: clientID, agent: agent.id, agentName: agent.displayName, sessionID: id, cwd: cwd, title: displayTitle, parentID: parentID)
    }

    var titleKey: SessionTitles.Key {
        SessionTitles.Key(agent: agent.id, session: id)
    }

    var isSubagent: Bool {
        parentID != nil
    }

    /// Whether the session has had a turn, so its agent has saved it and can reopen it.
    var hasStarted: Bool {
        lastStopReason != nil || phase == .prompting || state.items.contains { item in
            if case .message(let message) = item { message.role == .user } else { false }
        }
    }

    func child(_ id: SessionID) -> SessionModel? {
        children[id]
    }

    /// The session at the top of this one's chain of parents: the one the sidebar lists.
    var root: SessionModel {
        parent?.root ?? self
    }

    /// Whether the session takes prompts at all: the user's sessions and task sessions do, but an
    /// agent's own subagents only take work from their parent.
    var acceptsPrompts: Bool {
        origin != .announced
    }

    /// Whether the user's draft can go out now.
    var canSend: Bool {
        origin == .user && phase == .idle && !isRunningHiddenCommand && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether `cancel()` would stop anything: the current turn, or for an announced subagent, its
    /// work once the agent has said it can be cancelled.
    var canCancel: Bool {
        if origin == .announced {
            phase != .disconnected && parent?.subagentControls.canCancel(id) == true
        } else {
            phase == .prompting || isRetryScheduled
        }
    }

    /// Whether this session, or a subagent under it, is waiting on the user.
    var needsApproval: Bool {
        !state.pendingPermissions.isEmpty
            || !questions.isEmpty
            || subagentControls.isAnyWaitingOnUser
            || children.values.contains(where: \.needsApproval)
    }

    // MARK: - Agent events

    func apply(_ update: SessionUpdate) {
        if hiddenCommand?.capture(update) == true {
            return
        }
        if phase != .loading {
            switch update {
            case .subagent(let subagent): subagentControls.apply(subagent)
            case .usage(let usage): services.post(.usageUpdated(context, usage))
            default: break
            }
        }
        state.apply(update)
    }

    /// Creates the model for a subagent the agent just announced.
    func addSubagent(_ id: SessionID) -> SessionModel {
        let child = SessionModel(announced: id, by: self)
        children[id] = child
        return child
    }

    func requestPermission(_ request: RequestPermissionRequest, id: RequestID) {
        state.requestPermission(request, id: id)
    }

    func finishLoading(configOptions: [ConfigOption]?) {
        if let configOptions {
            state.configOptions = configOptions
        }
        phase = .idle
    }

    func failLoading(_ error: any Error) {
        state.appendNotice("Couldn't load this session: \(error.localizedDescription)", isError: true)
        phase = .idle
    }

    /// Cuts the session off from its agent, whose process went away. `isRestarting` says whether
    /// Native is bringing the agent back on its own.
    func markDisconnected(isRestarting: Bool = false) {
        guard phase != .disconnected else { return }
        let wasWorking = phase == .prompting
        phase = .disconnected
        // Whatever the subagents were doing is unknown now, and no one is left to answer.
        subagentControls.reset()
        questions.removeAll()
        let notice = switch (isRestarting, wasWorking) {
        case (true, true): "\(agentName) stopped unexpectedly in the middle of this turn. Native is restarting it and will ask it to pick up where it left off."
        case (true, false): "\(agentName) stopped unexpectedly. Native is restarting it."
        case (false, _): "\(agentName) stopped running. Restart it from the sidebar to continue."
        }
        state.appendNotice(notice, isError: true)
    }

    /// Adds a note to the transcript about something Native did, such as recovering the session.
    func addNotice(_ text: String, isError: Bool) {
        state.appendNotice(text, isError: isError)
    }

    // MARK: - Other actions

    /// Cancels the current turn. For a subagent, that stops only its work, never its parent's turn.
    func cancel() async {
        guard canCancel else { return }
        if isRetryScheduled {
            cancelRetry()
            state.appendNotice("Stopped retrying. Your message is still queued; send again to try it.", isError: false)
            return
        }
        // ACP requires answering open permission requests as cancelled when a turn is cancelled.
        for (toolCallID, _) in state.pendingPermissions {
            if let permission = state.resolvePermission(toolCallID: toolCallID) {
                try? await connection.respond(to: permission.requestID, with: RequestPermissionResponse.cancelled)
            }
        }
        await cancelQuestions()
        try? await connection.notify(CancelNotification(sessionId: id))
    }

    func choose(_ option: PermissionOption, forToolCall toolCallID: String) async {
        guard let permission = state.resolvePermission(toolCallID: toolCallID) else { return }
        try? await connection.respond(to: permission.requestID, with: RequestPermissionResponse.selected(optionId: option.optionId))
    }

    func setConfigOption(_ option: ConfigOption, to value: String) async {
        guard case .select(let current, let choices) = option.kind, current != value else { return }
        // Show the choice right away; the agent's answer is authoritative and replaces it.
        replaceConfigOption(option.id, with: .select(currentValue: value, options: choices))
        do {
            let response = try await connection.send(SetConfigOptionRequest(sessionId: id, configId: option.id, value: value))
            state.configOptions = response.configOptions
        } catch {
            replaceConfigOption(option.id, with: option.kind)
            state.appendNotice("Couldn't change \(option.name): \(error.localizedDescription)", isError: true)
        }
    }

    private func replaceConfigOption(_ id: String, with kind: ConfigOption.Kind) {
        guard let index = state.configOptions.firstIndex(where: { $0.id == id }) else { return }
        state.configOptions[index].kind = kind
    }
}
