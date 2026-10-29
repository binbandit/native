import ACP
import AppAppearance
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativePolicy
import Observation

/// One agent session: its transcript and settings, plus the user's actions on it. Turns (sending,
/// queueing, steering) live in `SessionModel+Turns.swift`, hidden commands in
/// `SessionModel+HiddenCommands.swift`.
///
/// A session runs either in Native's host (`host` is set: its transcript is a `SessionMirror` fed by
/// the host's events, and every action is a host request; see `SessionModel+Host.swift`), or in the
/// app, talking to the agent's own `connection`.
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
    private let chosenWorkingAnimation: WorkingAnimation

    /// Turning the option off restores the original grid without discarding this task's choice.
    var workingAnimation: WorkingAnimation? {
        services.workingSpinners.isEnabled ? chosenWorkingAnimation : nil
    }
    let cwd: URL
    let origin: Origin
    /// The session that started this one; `nil` for sessions the user started.
    let parentID: SessionID?
    /// Whether messages can join a turn that's running (`SteerRequest`).
    let supportsSteering: Bool
    var steeringGate = SteeringGate()
    var isDeliveringSteer = false
    var isSteeringBetweenSteps = false
    /// What the agent takes in a prompt besides text: images, embedded files.
    let promptCapabilities: PromptCapabilities
    var isChangingAgent = false
    var usesComposePresentation = false
    var isChangingWorkspace = false
    var isWorkspaceReplaced = false
    var isWorkspacePickerRequested = false
    /// Locks the folder before the first send suspends, including a queued or hidden prompt.
    var hasSubmittedPrompt = false
    /// What the composer holds. Saved as it changes, so it outlives the app (`ComposerDrafts`).
    var draft = "" {
        didSet { services.drafts.keep(draft, for: key) }
    }
    var diffCommentsPolicy: () -> NativePolicy = { PolicyCenter.shared.policy }
    var diffCommentEditors: [PromptQuote] = [] {
        didSet { services.drafts.keepCommentEditors(diffCommentEditors, for: key) }
    }
    var reanchoringDiffComment: UUID?
    var activeDiffComment: UUID?
    var diffCommentsExpanded = false
    var diffCommentEditsInComposer = false
    var diffCommentRequestedSource: PromptQuote?
    var diffCommentSelection: PromptQuote?
    var diffCommentFocusRequest = 0
    var diffCommentAnnouncement = ""
    var diffCommentAnnouncementGeneration = 0
    var diffCommentStatus: String?
    var diffCommentSending = false
    var unresolvedCommentPacket: String? {
        didSet { services.drafts.keepCommentDelivery(unresolvedCommentPacket, for: key) }
    }
    var quoteSelection: [PromptQuote] = []
    /// The current or latest model selection, shared by its source and replacement conversations.
    var modelChange: ComposerAgentChange?
    var attachmentReads = ComposerAttachmentReads()
    /// A model change replaces the transport conversation while retaining the task's view tree.
    var isModelChangeSource = false
    var continuedTaskKey: SessionKey?
    var taskPresentationKey: SessionKey { continuedTaskKey ?? key }
    var quoteSelectionSource: UUID?
    /// Files and images going out with the draft (SessionModel+Attachments.swift).
    var attachments: [PromptAttachment] = []
    /// The transient image and file viewer shared by this task's transcript styles.
    let artifactViewer = ArtifactViewerModel()
    /// Subagent sessions this one started, by their session id.
    private(set) var children: [SessionID: SessionModel] = [:]

    /// Asks the composer to take focus; the composer clears it once it has. A flag rather than a
    /// counter, so a request made while the composer is being created isn't lost.
    var wantsComposerFocus = false
    /// Set to ask the session's view to open the model picker; the view clears it.
    var isModelPickerRequested = false
    var isAgentPickerRequested = false
    /// Set to ask the composer to open its file picker (File ▸ Attach Files…); it clears it.
    var isAttachmentPickerRequested = false
    /// Set to ask the session's view to show or hide the subagent inspector; the view clears it.
    var isSubagentInspectorToggleRequested = false
    /// Set to scroll the transcript to an item and highlight it (search results); the transcript
    /// clears it.
    var transcriptReveal: TranscriptReveal?
    /// Shared by every view of this session, including return visits and subagent transcripts.
    let transcriptDisclosures = TranscriptDisclosures()

    // Turn state. Internal only so the SessionModel+ extensions in other files can drive turns;
    // everything else changes it through the methods.
    var state: SessionState {
        get {
            access(keyPath: \.state)
            return transcript
        }
        set {
            withMutation(keyPath: \.state) { transcript = newValue }
            mirrorState()
        }
        _modify {
            access(keyPath: \.state)
            _$observationRegistrar.willSet(self, keyPath: \.state)
            defer {
                _$observationRegistrar.didSet(self, keyPath: \.state)
                mirrorState()
            }
            yield &transcript
        }
    }
    /// Holds `state`'s value. History replayed while the session loads goes straight in here, and
    /// the transcript hears about it in batches (`noteReplayed()`): a long session replays thousands
    /// of updates one at a time, and the transcript lays itself out again on every change it sees.
    /// A host session folds the host's events into it; an in-app one, the agent's updates.
    @ObservationIgnored var mirror = SessionMirror()
    @ObservationIgnored private var replayNotice: Task<Void, Never>?
    private var transcript: SessionState {
        get { mirror.state }
        _modify { yield &mirror.state }
    }
    /// Parts of `state`, mirrored so what shows only these (the composer, sidebar rows, the status
    /// bar, menus) doesn't update with every streamed chunk, which changes `state`.
    private(set) var title: String?
    private(set) var configOptions: [ConfigOption] = []
    private(set) var plan: [PlanEntry] = []
    /// Mirrored independently of text chunks, so the toolbar doesn't render for each token.
    private(set) var taskActivity = TaskActivityNarration(verb: "Working")
    /// Kept with the task when its screen is left and reopened, so an already reviewed outcome rests.
    var reviewedTaskWellTurnID: String?
    private(set) var availableCommands: [AvailableCommand] = []
    private(set) var usage: Usage?
    /// Tool calls waiting for the user's permission, oldest first.
    private(set) var permissionRequests: [ToolCallState] = []
    private(set) var hasSubagents = false
    private(set) var isTranscriptEmpty = true
    /// Tool calls that may have written files and have finished (`SessionState.completedWriteCount`).
    private(set) var completedWriteCount = 0
    /// Whether history is still being replayed into the transcript: a load or reload under way, or
    /// this model catching up with a host session. The transcript shows a loading state meanwhile,
    /// never history arriving, and appears whole, at its end, once it's in.
    private(set) var isRestoringHistory = false
    /// An in-app session's load has answered, so its history is all in (its settings may still be
    /// on their way back).
    @ObservationIgnored private var hasLoadedHistory = false
    var phase: Phase {
        didSet {
            refreshRestoringHistory()
            if oldValue == .loading {
                announceReplay()
                // Drops what `shownConfigOptions` showed while it loaded, without taking the agent's
                // values as chosen: a load that failed or was cut off restores again next time.
                if configOptions != transcript.configOptions { configOptions = transcript.configOptions }
            }
        }
    }
    /// When the user last sent a prompt, for ordering the sidebar.
    var lastActivity: Date?
    /// How the latest turn ended: the agent's stop reason, or `.error` when the prompt request
    /// threw. Nil until a turn has ended.
    var lastStopReason: StopReason?
    var queue = PromptQueue() {
        didSet { reconcileQueuedEdit() }
    }
    /// The queued message open in the composer for editing, which ⌥⌘↑ / ⌥⌘↓ move.
    var editingQueuedPrompt: QueuedPrompt.ID? {
        get { queuedEdit.id }
        set { queuedEdit.id = newValue }
    }
    private var queuedEdit = PromptQueueEdit()

    private func reconcileQueuedEdit() {
        guard queuedEdit.id != nil else { return }
        queuedEdit.reconcile(with: queuedPrompts)
    }
    /// Stop was pressed and the agent hasn't ended the turn yet (SessionModel+Stop.swift).
    var isStopping = false
    @ObservationIgnored var stopRequestedAt: Date?
    @ObservationIgnored var stopTimeout: Task<Void, Never>?
    /// Counts turns, so the answer to a turn Native stopped waiting for doesn't end a later one.
    @ObservationIgnored var turnGeneration = 0
    var retryPolicy = TurnRetryPolicy()
    /// Waiting to send a prompt again after the network or the provider let it down.
    var isRetryScheduled = false
    @ObservationIgnored var retryTask: Task<Void, Never>?
    /// Questions the agent is waiting on (`elicitation/create`), oldest first; see
    /// SessionModel+Questions.
    var questions: [PendingQuestion] = []
    @ObservationIgnored var questionsBeingAnswered: Set<RequestID> = []
    /// While a hidden command runs: the session takes no new turn, but its phase stays idle.
    var isRunningHiddenCommand = false
    @ObservationIgnored var hiddenCommand: HiddenCommandCapture?
    /// The last hidden command's reply, until the next turn starts, so copies of it that arrive after
    /// its turn ended stay out of the transcript too.
    @ObservationIgnored var hiddenCommandEcho: HiddenCommandCapture?
    /// The agent's connection, for a session Native runs in the app; nil for one in the host.
    let connection: ACPConnection?
    /// Where the session runs in Native's host; nil for one in the app.
    let host: HostSessionLink?
    let services: SessionServices
    /// What the host last said about the session (its queue, whether it's stopping, retrying or
    /// running a hidden command), for a host session (SessionModel+Host.swift).
    var hostSummary: HostSessionSummary? {
        didSet {
            refreshRestoringHistory()
            reconcileQueuedEdit()
        }
    }
    /// Messages held here until the session can take them: while it loads and its settings are
    /// set back, and while a workspace hold lasts (SessionModel+Host.swift).
    var heldPrompts: [HeldPrompt] = [] {
        didSet { reconcileQueuedEdit() }
    }
    /// Set while host events that happened before this model followed the session are applied, so
    /// they rebuild the transcript without telling plugins about them again.
    @ObservationIgnored var isReplaying = false {
        didSet { refreshRestoringHistory() }
    }
    /// Set while a host session that just loaded gets its chosen settings back; it shows as still
    /// loading meanwhile, as an in-app session does (SessionModel+ConfigRestore.swift).
    var isSettingBackConfig = false
    /// Questions answered here whose answer the host hasn't confirmed yet, kept out of `questions`.
    @ObservationIgnored var answeredQuestions: Set<String> = []

    @ObservationIgnored private weak var parent: SessionModel?
    var subagentControls = SubagentControls()

    /// A session of `agent`, the user's or (`origin: .task`) one Native's tools started. A task's
    /// `parent` adopts it as a subagent.
    init(
        agent: AgentDefinition, id: SessionID, clientID: UUID = UUID(), cwd: URL, connection: ACPConnection?,
        services: SessionServices, supportsSteering: Bool,
        promptCapabilities: PromptCapabilities = PromptCapabilities(), phase: Phase,
        title: String? = nil, configOptions: [ConfigOption] = [], origin: Origin = .user, parent: SessionModel? = nil
    ) {
        self.agent = agent
        self.id = id
        chosenWorkingAnimation = services.workingSpinners.animation(agentID: agent.id.rawValue, taskID: id.rawValue)
        self.clientID = clientID
        self.cwd = cwd
        self.connection = connection
        host = nil
        self.services = services
        self.supportsSteering = supportsSteering
        self.promptCapabilities = promptCapabilities
        self.phase = phase
        self.origin = origin
        parentID = parent?.id
        self.parent = parent
        transcript.title = title
        transcript.configOptions = configOptions
        mirrorState()
        parent?.children[id] = self
    }

    /// A session running in Native's host, as its summary describes it. Its transcript arrives as
    /// the host's events (`receive(_:)`), and `parent` adopts it as a subagent.
    init(
        agent: AgentDefinition, id: SessionID, summary: HostSessionSummary, client: NativeHostClient,
        services: SessionServices, promptCapabilities: PromptCapabilities, origin: Origin, parent: SessionModel?
    ) {
        self.agent = agent
        self.id = id
        chosenWorkingAnimation = services.workingSpinners.animation(agentID: agent.id.rawValue, taskID: id.rawValue)
        clientID = summary.id.rawValue
        cwd = URL(filePath: summary.cwd, directoryHint: .isDirectory)
        connection = nil
        host = HostSessionLink(client: client, id: summary.id)
        self.services = services
        supportsSteering = summary.supportsSteering
        self.promptCapabilities = promptCapabilities
        phase = Self.phase(of: summary, isSettingBackConfig: false)
        self.origin = origin
        parentID = parent?.id
        self.parent = parent
        hostSummary = summary
        lastActivity = summary.lastActivity
        lastStopReason = summary.lastStopReason.map(SessionMirror.stopReason)
        transcript.title = summary.title
        mirrorState()
        parent?.children[id] = self
    }

    private init(announced id: SessionID, by parent: SessionModel, host: HostSessionSummary? = nil) {
        agent = parent.agent
        self.id = id
        clientID = host?.id.rawValue ?? UUID()
        cwd = parent.cwd
        connection = parent.connection
        self.host = host.flatMap { summary in parent.host.map { HostSessionLink(client: $0.client, id: summary.id) } }
        hostSummary = host
        services = parent.services
        chosenWorkingAnimation = parent.services.workingSpinners.animation(
            agentID: parent.agent.id.rawValue, taskID: id.rawValue)
        supportsSteering = false
        promptCapabilities = PromptCapabilities()
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
        return services.titles.title(for: titleKey, agentTitle: title) ?? (origin == .task ? "Task" : "New Task")
    }

    /// This session as plugins see it.
    var context: SessionContext {
        SessionContext(
            clientID: clientID, agent: agent.id, agentName: agent.displayName, sessionID: id, cwd: cwd,
            title: displayTitle, parentID: parentID)
    }

    var titleKey: SessionTitles.Key {
        SessionTitles.Key(agent: agent.id, session: id)
    }

    var isSubagent: Bool {
        parentID != nil
    }

    /// Whether the session has had a turn, so its agent has saved it and can reopen it.
    var hasStarted: Bool {
        lastStopReason != nil || phase == .prompting
            || state.items.contains { item in
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
    /// agent's own subagents only take work from their parent, and a conversation `/clear` set aside
    /// is kept to read.
    var acceptsPrompts: Bool {
        origin != .announced && !isEarlierConversation && !isChangingAgent
            && !isChangingWorkspace && !isWorkspaceReplaced
    }

    /// What the session's turns wait for outside it, such as "the worktree's setup script". Messages
    /// sent meanwhile queue, and go out once it's lifted.
    var turnHold: String? {
        services.sendGate.workspaceHold(for: cwd)
    }

    /// Whether the user's draft can go out now.
    var canSend: Bool {
        origin == .user && acceptsPrompts && phase == .idle && !isRunningHiddenCommand && turnHold == nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        !permissionRequests.isEmpty
            || !questions.isEmpty
            || subagentControls.isAnyWaitingOnUser
            || children.values.contains(where: \.needsApproval)
    }

    // MARK: - Agent events

    func apply(_ update: SessionUpdate) {
        if hiddenCommand?.capture(update) == true {
            return
        }
        if phase == .idle, hiddenCommandEcho?.isEcho(update) == true {
            return
        }
        if phase != .loading {
            switch update {
            case .subagent(let subagent): subagentControls.apply(subagent)
            case .usage(let usage): services.post(.usageUpdated(context, usage))
            case .configOptions(let options): AgentSessionDefaults.remember(options, for: agent.id)
            default: break
            }
        }
        if phase == .loading {
            transcript.apply(update)
            mirrorState()
            noteReplayed()
        } else {
            state.apply(update)
            if host == nil, phase == .prompting {
                steeringGate.apply(update)
                deliverPendingSteer()
            }
        }
    }

    /// Tells `state`'s observers about history replayed after the transcript shows (a host session
    /// setting its settings back) at most every 100 ms. While history is being restored nobody
    /// hears about it: the transcript waits for all of it (`refreshRestoringHistory()`).
    func noteReplayed() {
        guard !isRestoringHistory, replayNotice == nil else { return }
        replayNotice = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.announceReplay()
        }
    }

    func announceReplay() {
        guard replayNotice != nil else { return }
        replayNotice?.cancel()
        replayNotice = nil
        withMutation(keyPath: \.state) {}
    }

    /// Brings `isRestoringHistory` up to date. When the history is all in, `state`'s observers hear
    /// about all of it at once.
    func refreshRestoringHistory() {
        let isRestoring =
            if host != nil {
                isReplaying || mirror.isLoading || hostSummary?.phase == .loading
            } else {
                phase == .loading && !hasLoadedHistory
            }
        guard isRestoring != isRestoringHistory else { return }
        isRestoringHistory = isRestoring
        if !isRestoring {
            replayNotice?.cancel()
            replayNotice = nil
            withMutation(keyPath: \.state) {}
        }
    }

    /// Writes only what changed, since writing notifies observers even with an equal value.
    func mirrorState() {
        reconcileDiffCommentDelivery()
        if title != transcript.title {
            title = transcript.title
        }
        let shownOptions = shownConfigOptions(transcript.configOptions)
        if configOptions != shownOptions {
            configOptions = shownOptions
            // A loading session reports the agent's defaults until its settings are set back, and
            // shows the settings it's getting back meanwhile (SessionModel+ConfigRestore.swift);
            // after that, chosen settings follow the session. A host session also replays history
            // (a reload, or its log when this model starts following it) that reports the agent's
            // defaults ahead of the set-back, so only what it reports live is followed.
            let report: ConfigChoices.Report =
                phase == .loading || isReplaying || mirror.isLoading || isSettingBackConfig ? .history : .live
            services.titles.updateConfigChoices(for: titleKey) { $0.follow(configOptions, from: report) }
        }
        if plan != transcript.plan { plan = transcript.plan }
        let activity = transcript.taskActivity
        if taskActivity != activity { taskActivity = activity }
        if availableCommands != transcript.availableCommands { availableCommands = transcript.availableCommands }
        if usage != transcript.usage { usage = transcript.usage }
        let requests = transcript.permissionRequests
        if permissionRequests != requests {
            permissionRequests = requests
            services.hooks.approvalsChanged(self, requests)
        }
        if hasSubagents != transcript.hasSubagents { hasSubagents = transcript.hasSubagents }
        if isTranscriptEmpty != transcript.items.isEmpty { isTranscriptEmpty = transcript.items.isEmpty }
        if completedWriteCount != transcript.completedWriteCount {
            completedWriteCount = transcript.completedWriteCount
        }
        refreshRestoringHistory()
        if host != nil {
            mirrorHostQuestions()
        }
    }

    /// Creates the model for a subagent the agent just announced; in the host, the session the host
    /// made for it.
    func addSubagent(_ id: SessionID, host: HostSessionSummary? = nil) -> SessionModel {
        let child = SessionModel(announced: id, by: self, host: host)
        children[id] = child
        return child
    }

    func requestPermission(_ request: RequestPermissionRequest, id: RequestID) {
        if host == nil, phase == .prompting { steeringGate.apply(.toolCallUpdate(request.toolCall)) }
        state.requestPermission(request, id: id)
    }

    func finishLoading(configOptions: [ConfigOption]?) async {
        hasLoadedHistory = true
        refreshRestoringHistory()
        if let configOptions {
            state.configOptions = configOptions
        }
        // Still loading while the settings are set back, so nothing queued goes out without them.
        await restoreConfigChoices()
        // The agent may have gone away meanwhile.
        guard phase == .loading else { return }
        phase = .idle
        services.titles.updateConfigChoices(for: titleKey) { $0.follow(state.configOptions) }
        // Messages sent while it loaded.
        drainQueue()
    }

    func failLoading(_ error: any Error) {
        hasLoadedHistory = true
        state.appendNotice(
            "Couldn't load this task: \(error.localizedDescription.withoutTerminalEscapes)", isError: true)
        phase = .idle
    }

    /// Cuts the session off from its agent, whose process went away. `isRestarting` says whether
    /// Native is bringing the agent back on its own.
    func markDisconnected(isRestarting: Bool = false) {
        guard phase != .disconnected else { return }
        if isStopping { explainUnconfirmedStop() }
        let wasWorking = phase == .prompting
        phase = .disconnected
        // Whatever the subagents were doing is unknown now, and no one is left to answer.
        subagentControls.reset()
        questions.removeAll()
        let notice =
            switch (isRestarting, wasWorking) {
            case (true, true):
                "\(agentName) stopped unexpectedly in the middle of this turn. Native is restarting it and will ask it to pick up where it left off."
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

    func choose(_ option: PermissionOption, forToolCall toolCallID: String) async {
        guard let permission = state.resolvePermission(toolCallID: toolCallID) else { return }
        // Native's own approvals (SessionModel+ScriptApprovals.swift) never reached the agent.
        guard !NativeApprovals.isNative(permission.requestID) else {
            return NativeApprovals.answer(permission.requestID, with: option)
        }
        if let host {
            return await host.respondPermission(toolCallID: toolCallID, optionID: option.optionId)
        }
        try? await connection?.respond(
            to: permission.requestID, with: RequestPermissionResponse.selected(optionId: option.optionId))
    }

    func setConfigOption(_ option: ConfigOption, to value: String) async {
        guard case .select(let current, let choices) = option.kind, current != value else { return }
        // Every way of changing a setting comes through here, so a forbidden permission mode stops here.
        guard !PolicyPermissionModes.forbids(option, value: value) else { return }
        // Remembered for reopening the session; from here on it follows what the agent reports.
        services.titles.updateConfigChoices(for: titleKey) { $0.choose(option, value: value) }
        // Show the choice right away; the agent's answer is authoritative and replaces it.
        replaceConfigOption(option.id, with: .select(currentValue: value, options: choices))
        do {
            if let host {
                // The agent's answer arrives as an update before the host answers.
                try await host.setConfigOption(option.id, to: value)
            } else if let connection {
                let response = try await connection.send(
                    SetConfigOptionRequest(sessionId: id, configId: option.id, value: value))
                state.configOptions = response.configOptions
            }
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
