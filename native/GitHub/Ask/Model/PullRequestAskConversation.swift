import ACP
import AIInstructions
import Foundation
import GitHub
import Observation

/// One pull request's private conversation with an agent: questions go to a read-only task
/// session (out of the sidebar) whose first message carries the pull request's context, and
/// follow-ups continue it. Nothing here posts to GitHub; an answer only becomes a comment draft
/// when the user asks, and only posts when they press Comment. Gathering the context lives in
/// `+Context`.
@Observable
final class PullRequestAskConversation {
    /// What's under way before the agent has the question.
    enum Activity: Equatable {
        case idle
        /// Loading the diffs and conversation the context needs.
        case gathering
        /// Starting the agent's session, or reopening the earlier one.
        case connecting(reopening: Bool)
    }

    let reference: PullRequestReference
    private(set) var record: PullRequestAskRecord?
    private(set) var session: SessionModel? {
        didSet {
            if session !== oldValue { watchForCrash() }
        }
    }
    private(set) var activity = Activity.idle
    /// Why the last question couldn't go out; it waits in `draft` until this is fixed.
    private(set) var failure: PullRequestAskFailure?
    /// Waiting for a crashed agent to restart, to reopen the conversation and finish the answer.
    private(set) var isRecovering = false
    /// Whether the agent is in a mode that can't change anything. False only when it has no such
    /// mode, which the panel says.
    private(set) var isReadOnly = true
    /// The question being written.
    var draft = ""
    /// Asks the composer to take focus; it clears this once it has.
    var wantsComposerFocus = false
    /// The question on its way while the context loads or the session starts, before the agent
    /// has it, so the panel shows it at once.
    private(set) var pendingQuestion: String?
    /// "Started a new conversation", with Undo.
    var undo: UndoToastItem?

    @ObservationIgnored unowned let center: PullRequestAskCenter
    @ObservationIgnored private var crashWatch: Task<Void, Never>?

    init(reference: PullRequestReference, record: PullRequestAskRecord?, center: PullRequestAskCenter) {
        self.reference = reference
        self.record = record
        self.center = center
    }

    var isBusy: Bool {
        activity != .idle
    }

    /// Whether the agent is answering, so the composer offers Stop.
    var isAnswering: Bool {
        session?.phase == .prompting
    }

    var canSend: Bool {
        !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The agent that answers: the session's, or the one a new conversation would start with.
    var agentName: String {
        session?.agentName ?? record.flatMap { center.app?.runtime($0.key.agent)?.agent.displayName }
            ?? center.app?.defaultAgent?.displayName ?? "The agent"
    }

    // MARK: - Asking

    /// Sends the draft.
    func send() async {
        await ask(draft)
    }

    /// Asks `question`: the first one starts the conversation with the pull request's context;
    /// later ones continue it, bringing new commits in first. While the agent answers, it's queued.
    func ask(_ question: String) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy, center.app != nil else { return }
        failure = nil
        draft = ""
        pendingQuestion = question
        defer { pendingQuestion = nil }
        do {
            if let session = try await liveSession() {
                try await followUp(question, in: session)
            } else {
                try await begin(question)
            }
        } catch {
            failure =
                error as? PullRequestAskFailure ?? .startFailed(name: agentName, message: error.localizedDescription)
            // Nothing the user wrote is lost.
            if draft.isEmpty { draft = question }
        }
        activity = .idle
    }

    /// Asks the question a failure held back, once its fix (a sign-in, an agent) is in.
    func retry() async {
        await ask(draft)
    }

    /// Asks the last question again, after the agent failed or stopped mid-answer.
    func askAgain() async {
        guard let question = lastQuestion else { return }
        await ask(question)
    }

    func stop() async {
        await session?.cancel()
    }

    /// Shows the earlier conversation when the panel opens, reopening its session if needed.
    func restore() async {
        guard record != nil, session == nil, !isBusy, failure == nil else { return }
        do {
            _ = try await liveSession()
        } catch {
            failure =
                error as? PullRequestAskFailure ?? .reopenFailed(name: agentName, message: error.localizedDescription)
        }
        activity = .idle
    }

    /// Starts over: the next question opens a fresh conversation. The old one stays in the agent's
    /// history and in search; Undo brings it back here.
    func startOver() {
        guard let previous = record else { return }
        let previousSession = session
        record = nil
        session = nil
        failure = nil
        center.records[reference] = nil
        undo = UndoToastItem("Started a new conversation") { [weak self] in
            guard let self, record == nil else { return }
            record = previous
            session = previousSession
            center.records[reference] = previous
        }
    }

    /// The user's last question, read back from the transcript.
    var lastQuestion: String? {
        session?.state.items.reversed().lazy.compactMap { item -> String? in
            guard case .message(let message) = item, message.role == .user else { return nil }
            return PullRequestAskPrompt.message(message.text)?.question ?? message.text
        }.first
    }

    // MARK: - Sessions

    /// The session to continue, reopened from the agent if it isn't open. Nil when there's no
    /// conversation yet.
    private func liveSession() async throws -> SessionModel? {
        guard let app = center.app else { return nil }
        if let session, app.session(session.key) === session, session.phase != .disconnected {
            return session
        }
        guard let record else { return nil }
        activity = .connecting(reopening: true)
        // The agent can't load a session whose folder is gone (caches cleared, say); an empty one
        // will do, and the next question brings the context back.
        try await ensureFolder(record.folder)
        let session: SessionModel
        do {
            session = try await app.reopenTaskSession(agent: record.key.agent, id: record.key.id, cwd: record.folder)
        } catch {
            throw failure(for: error, agent: record.key.agent, reopening: true)
        }
        isReadOnly = await PullRequestAskMode.apply(to: session)
        self.session = session
        return session
    }

    private func begin(_ question: String) async throws {
        guard let app = center.app else { return }
        activity = .gathering
        let (source, context) = try await gatherContext()
        let folder = center.folder(for: reference)
        try await save(context, to: folder)
        activity = .connecting(reopening: false)
        if app.defaultAgent == nil { await app.agentsChecked() }
        guard let agent = app.defaultAgent?.id else { throw PullRequestAskFailure.noAgent }
        let session: SessionModel
        do {
            session = try await app.startTaskSession(agent: agent, cwd: folder)
        } catch {
            throw failure(for: error, agent: agent, reopening: false)
        }
        isReadOnly = await PullRequestAskMode.apply(to: session)
        // Named for the pull request, as search lists it, rather than after the framed first message.
        app.titles.rename(session.titleKey, to: "Questions about \(reference.display)")
        self.session = session
        let record = PullRequestAskRecord(
            key: session.key, folder: folder, headRefOid: source.headRefOid, inclusion: context.inclusion,
            startedAt: .now)
        self.record = record
        center.records[reference] = record
        // The conversation runs in a folder of its own, outside any project: the global instructions apply.
        let instructions = AIInstructionsStore.shared.addition(for: .pullRequestQuestions, in: nil)
        try await session.submit(
            PullRequestAskPrompt.opening(question, context: context, source: source, adding: instructions), .queue)
    }

    private func followUp(_ question: String, in session: SessionModel) async throws {
        var refreshed: PullRequestAskContext?
        // New commits since the agent last saw the pull request: it gets them before the question.
        if var record, let page = await currentPage(), page.headRefOid != record.headRefOid {
            activity = .gathering
            let (source, context) = try await gatherContext()
            try await save(context, to: record.folder)
            record.headRefOid = source.headRefOid
            record.inclusion = context.inclusion
            self.record = record
            center.records[reference] = record
            refreshed = context
        }
        activity = .idle
        try await session.submit(PullRequestAskPrompt.followUp(question, refreshed: refreshed), .queue)
    }

    /// The failure to show for a session that wouldn't start or reopen.
    private func failure(for error: any Error, agent: AgentDefinition.ID, reopening: Bool) -> PullRequestAskFailure {
        let runtime = center.app?.runtime(agent)
        let name = runtime?.agent.displayName ?? agent.rawValue
        if let runtime, runtime.needsSignIn, !runtime.authMethods.isEmpty {
            return .signInRequired(agent: agent, name: name)
        }
        if let runtime, runtime.status.canRetry {
            return .agentUnavailable(agent: agent, name: name, guidance: runtime.status.guidance)
        }
        let message = (error as? SessionLauncher.LaunchError).map(Self.underlying) ?? error.localizedDescription
        return reopening
            ? .reopenFailed(name: name, message: message.withoutTerminalEscapes)
            : .startFailed(name: name, message: message.withoutTerminalEscapes)
    }

    private static func underlying(_ error: SessionLauncher.LaunchError) -> String {
        if case .failed(_, let underlying) = error {
            underlying.localizedDescription
        } else {
            error.localizedDescription
        }
    }

    // MARK: - The agent stopping mid-answer

    /// Catches the agent's process dying mid-answer. The app restarts the agent but only reopens
    /// sidebar sessions, so this reopens the conversation once the new process is up and asks the
    /// agent to finish, saying so in the panel. If the agent doesn't come back, the panel's
    /// "stopped running" state offers Ask Again.
    private func watchForCrash() {
        crashWatch?.cancel()
        guard let session else { return }
        crashWatch = Task { [weak self, weak session] in
            var previous: SessionModel.Phase?
            for await phase in Observations({ session?.phase }) {
                defer { previous = phase }
                guard phase == .disconnected, previous == .prompting, let self, let session else { continue }
                await self.resume(after: session)
                return
            }
        }
    }

    private func resume(after crashed: SessionModel) async {
        guard let app = center.app else { return }
        isRecovering = true
        defer { isRecovering = false }
        let agent = crashed.key.agent
        // Ready means the app's recovery is done with the agent's old sessions, this one included.
        for _ in 0..<Self.recoveryChecks {
            if app.runtime(agent)?.isReady == true, app.session(crashed.key) !== crashed { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard session === crashed, app.runtime(agent)?.isReady == true, app.session(crashed.key) !== crashed,
            !isBusy
        else { return }
        do {
            guard let session = try await liveSession() else { return }
            try await session.submit(AppModel.interruptedTurnPrompt, .queue, echo: false)
            session.addNotice(
                "\(agentName) stopped in the middle of this answer. Native restarted it and asked it to finish. Use Stop if you'd rather it didn't.",
                isError: false)
        } catch {
            failure =
                error as? PullRequestAskFailure ?? .reopenFailed(name: agentName, message: error.localizedDescription)
        }
        activity = .idle
    }

    /// How long to wait for the app to restart a crashed agent, in half seconds.
    private static let recoveryChecks = 60

    // MARK: - Fixing what stopped a question

    /// How `agent` can sign in, for the sign-in failure's buttons.
    func signInMethods(for agent: AgentDefinition.ID) -> [AuthMethod] {
        center.app?.runtime(agent)?.authMethods ?? []
    }

    /// Runs the agent's own sign-in, then asks the held question. A sign-in that has to happen in a
    /// terminal opens the app's sheet for it; the question waits for Try Again.
    func signIn(to agent: AgentDefinition.ID, with method: AuthMethod) async {
        guard let app = center.app else { return }
        if await app.signIn(to: agent, with: method) {
            await retry()
        }
    }

    /// Starts an agent that stopped (or checks again for one that wasn't installed), then asks again.
    func restartAgent(_ agent: AgentDefinition.ID) async {
        guard let app = center.app else { return }
        if case .notInstalled = app.runtime(agent)?.status {
            await app.checkForAgents()
        } else {
            await app.restart(agent)
        }
        await retry()
    }

    /// Opens Add Agent, for when none is installed.
    func addAgent() {
        center.app?.isAddingAgent = true
    }

    // MARK: - Comments

    /// Puts `text` (an answer, or part of one) in the pull request's comment box on Conversation,
    /// below anything already there, and shows it. Never posts: the user edits it and presses
    /// Comment. Undo puts the box back as it was.
    func draftComment(_ text: String) {
        guard let gitHub = center.gitHub, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let page = gitHub.pageModel(for: reference)
        let previous = page.conversationDraft
        page.draftConversationComment(text)
        page.undo = UndoToastItem("Added to your comment draft. Nothing is posted until you choose Comment.") {
            [weak page] in
            page?.conversationDraft = previous
        }
    }
}
