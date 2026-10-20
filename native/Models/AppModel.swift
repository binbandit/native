import ACP
import Foundation
import Observation
import os

/// The app's state, composed of focused parts: the agents plugins provide (`AgentRuntimes`), the
/// projects (`Projects`), the sessions agents list for them (`SessionCatalog`, ordered by
/// `SessionOrdering`) and the ones open (`SessionStore`). This type coordinates them for the
/// views: starting sessions, selection and its history, and the app-level prompts.
@Observable
final class AppModel {
    let plugins: PluginRegistry
    let titles: SessionTitles
    let runtimes: AgentRuntimes
    let projects: Projects
    let catalog: SessionCatalog
    let ordering: SessionOrdering
    let sessions: SessionStore
    let unread: UnreadSessions
    let archivedSessions = ArchivedSessions()
    /// Conversations `/clear` set aside (AppModel+ClearConversation.swift).
    let earlierConversations = EarlierConversations()
    /// Makes and removes the folders tasks run in (worktrees). Set by the app from the Git feature;
    /// without it tasks run in the project folder.
    weak var taskWorkspaces: (any TaskWorkspaceProvider)?
    /// The latest action the user can take back, for the window's undo toast.
    var lastUndoable: UndoableAction?
    /// Features that keep sessions out of the sidebar claim them here (a pull request's private
    /// questions), so a session search found opens their way instead of as a task under a project.
    /// Each gets the session and its folder, and returns whether it opened the session.
    @ObservationIgnored var searchedSessionOpeners: [@MainActor (SessionKey, _ cwd: String) -> Bool] = []

    var selection: SessionKey? {
        didSet {
            guard let selection else { return }
            unread.set(selection, unread: false)
            if !isNavigatingHistory, selection != oldValue {
                history.visit(selection)
            }
        }
    }
    /// The sidebar row whose title is being edited.
    var renaming: SessionKey?
    /// Whether the folder picker for adding a project is showing.
    var isAddingProject = false
    /// Whether the agent picker for a new session is showing.
    var isChoosingAgent = false
    /// Whether Add Agent (agents that aren't installed, and how to install them) is showing.
    var isAddingAgent = false
    /// Which agents are installed. Ones that aren't are offered in Add Agent and never started.
    let installations = AgentInstallations()
    /// An agent that wants the user to sign in before it starts a session.
    var signInPrompt: AgentDefinition.ID?
    /// A sign-in under way in a terminal, for agents that can only sign in there.
    var terminalSignIn: AgentTerminalSignIn?
    /// An action the user just took that failed (starting a session, signing in), for the window's
    /// alert. Work Native does on its own reports to `problems` instead, never here.
    var actionFailure: ActionFailure?
    /// Background work that failed for a project, shown with the project until it's fixed.
    let problems = ProjectProblems()
    /// Listed tasks that couldn't be opened before they had a model, shown in their place (a load
    /// that fails later says so in the task's transcript).
    var openFailures: [SessionKey: SessionOpenFailure] = [:]
    /// Tasks the user asked for whose session doesn't exist yet, newest first
    /// (AppModel+StartingTasks.swift).
    var startingTasks: [StartingTask] = []
    /// Each project's latest workspace preparation, so new tasks' git work runs one at a time per
    /// project. Internal only for AppModel+StartingTasks.swift.
    @ObservationIgnored var workspacePreparations: [Project.ID: Task<Void, Never>] = [:]
    /// Each project's listings (`session/list`) under way, for "Finding sessions…". Internal only
    /// for AppModel+Listing.swift.
    var projectListingsInFlight: [Project.ID: Int] = [:]
    /// The project whose home was shown last, for when no session is selected. Internal only for
    /// AppModel+Projects.swift.
    var focusedProjectID: Project.ID?

    // Internal only for the AppModel+ extensions.
    /// Deletions waiting out their undo window.
    @ObservationIgnored var pendingDeletions: [SessionKey: Task<Void, Never>] = [:] {
        didSet { pendingDeletionKeys = Set(pendingDeletions.keys) }
    }
    private(set) var pendingDeletionKeys: Set<SessionKey> = []
    @ObservationIgnored var pendingProjectDeletions: [Project.ID: Task<Void, Never>] = [:]
    /// Each task folder's workspace work under way (putting it away, bringing it back), by path, so
    /// the next waits for it. Internal only for AppModel+Archive.swift.
    @ObservationIgnored var workspaceWork: [String: Task<Void, Never>] = [:]
    /// When each unarchived task was archived, until its workspace is back: it tells that archive's
    /// checkpoint from earlier ones when nothing was recorded. Internal only for AppModel+Archive.swift.
    @ObservationIgnored var archiveDatesAwaitingRestore: [SessionKey: Date] = [:]
    /// Tasks whose workspace was removed outside Native while their work isn't done, for the
    /// sidebar and the task (AppModel+RemovedWorkspaces.swift).
    var removedWorkspaces: [SessionKey: RemovedWorkspace] = [:]
    /// Removed workspaces being restored. Internal only for AppModel+RemovedWorkspaces.swift.
    var restoringRemovedWorkspaces: Set<SessionKey> = []
    @ObservationIgnored var removedWorkspaceCheck: Task<Void, Never>?
    @ObservationIgnored var isRemovedWorkspaceCheckDue = false
    @ObservationIgnored let deletedSessions = DeletedSessions()
    var history = NavigationHistory<SessionKey>()
    @ObservationIgnored var isNavigatingHistory = false

    private var lastUsedAgent: AgentDefinition.ID?
    /// Internal only for AppModel+Recovery.swift.
    @ObservationIgnored var restartPolicies: [AgentDefinition.ID: AgentRestartPolicy] = [:]
    @ObservationIgnored private let services: SessionServices
    /// Where features take part in every session (`SessionHooks`), filled in at launch.
    var sessionHooks: SessionHooks { services.hooks }
    /// Internal only for AppModel+TaskSessions.swift.
    @ObservationIgnored let launcher: SessionLauncher
    /// Internal only for AppModel+Listing.swift.
    @ObservationIgnored let taskRecords = TaskSessionRecords()
    /// Task sessions being started, by agent, whose ids aren't known yet. Internal only for
    /// AppModel+TaskSessions.swift and AppModel+Listing.swift.
    @ObservationIgnored var taskStartsInFlight: [AgentDefinition.ID: Int] = [:]
    /// Listings (`session/list`) under way, by agent, so an idle agent isn't stopped mid-listing.
    /// Internal only for AppModel+Listing.swift and AppModel+AgentLifecycle.swift.
    @ObservationIgnored var listingsInFlight: [AgentDefinition.ID: Int] = [:]
    @ObservationIgnored private let environment = ShellEnvironment()
    /// What stops an agent's sessions from taking messages; the Usage feature reports limits here.
    let sendGate: AgentSendGate
    /// Internal only for AppModel+Listing.swift.
    let sessionLists = ProjectSessionLists()
    @ObservationIgnored private let pluginEvents: AsyncStream<SessionEvent>
    @ObservationIgnored private let titleEvents: AsyncStream<TitleEvent>
    /// Tasks whose workspace has been told its title, so it's told only once. Internal only for
    /// AppModel+Titles.swift.
    @ObservationIgnored var titledWorkspaces: Set<SessionKey> = []

    struct TitleEvent {
        let key: SessionKey
        let folder: URL
        let title: String
    }

    /// What failed, as an alert's title ("Couldn't Start a Session"), and why, as its message.
    struct ActionFailure {
        let title: String
        let message: String

        init(_ title: String, _ message: String) {
            self.title = title
            self.message = message
        }
    }
    @ObservationIgnored private var isStarted = false
    /// Whether the first check for installed agents has made their runtimes. Internal only for
    /// AppModel+AgentLifecycle.swift, as is `agentCheckWaiters`.
    private(set) var hasCheckedAgents = false
    @ObservationIgnored var agentCheckWaiters: [CheckedContinuation<Void, Never>] = []

    private static let lastUsedAgentKey = "defaultAgent"
    static let logger = Logger(subsystem: "Native", category: "Sessions")

    init(plugins: PluginRegistry = PluginRegistry(), titles: SessionTitles = SessionTitles()) {
        // Writing to an agent that just exited must surface as an error, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        self.plugins = plugins
        self.titles = titles
        let (pluginEvents, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        self.pluginEvents = pluginEvents
        let (titleEvents, titleContinuation) = AsyncStream.makeStream(of: TitleEvent.self)
        self.titleEvents = titleEvents
        let sendGate = AgentSendGate()
        self.sendGate = sendGate
        services = SessionServices(
            plugins: plugins, titles: titles, sendGate: sendGate, earlierConversations: earlierConversations
        ) {
            continuation.yield($0)
        } titleLanded: { key, folder, title in
            titleContinuation.yield(TitleEvent(key: key, folder: folder, title: title))
        }
        runtimes = AgentRuntimes(plugins: plugins)
        sendGate.runtimes = runtimes
        projects = Projects()
        catalog = SessionCatalog()
        ordering = SessionOrdering()
        sessions = SessionStore(services: services)
        unread = UnreadSessions()
        launcher = SessionLauncher(plugins: plugins, services: services, store: sessions)
        lastUsedAgent = UserDefaults.standard.string(forKey: Self.lastUsedAgentKey).map(
            AgentDefinition.ID.init(rawValue:))
        // Agents with saved sessions were installed last time. Their runtimes come now, so their
        // rows show from the first frame, not once the host connects and the login shell answers;
        // they run in the host if one connects before they start, and checking for agents drops
        // any that went away since.
        _ = runtimes.sync(including: catalog.hasSessions)
    }

    /// Ends every agent's process, for when the app quits.
    func stopAgents() {
        runtimes.stopAll()
    }

    // MARK: - Agents

    /// The agent new sessions start with unless the user picks another: the one used last, or
    /// while that one can't start sessions, the first that can.
    var defaultAgent: AgentDefinition? {
        let lastUsed = agents.first { $0.agent.id == lastUsedAgent }
        if let lastUsed, lastUsed.isAvailable { return lastUsed.agent }
        return (agents.first(where: \.isAvailable) ?? lastUsed ?? agents.first)?.agent
    }

    /// The agent a new task in `project` starts with unless the user picks another: the project's
    /// own (Settings ▸ Projects) while it can start sessions, else `defaultAgent`.
    func defaultAgent(in project: Project?) -> AgentDefinition? {
        if let project, let id = ProjectTaskDefaults.agent(for: project.id), let runtime = runtimes[id],
            runtime.isAvailable
        {
            return runtime.agent
        }
        return defaultAgent
    }

    /// Makes `agent` the one new sessions start with. Internal only for AppModel+StartingTasks.swift.
    func rememberLastUsed(_ agent: AgentDefinition.ID) {
        lastUsedAgent = agent
        UserDefaults.standard.set(agent.rawValue, forKey: Self.lastUsedAgentKey)
    }

    /// Starts the agents worth having running (`agentsWorthStarting`), and keeps up as plugins come
    /// and go. The rest start when something needs them.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        // Before anything asks the host for work, so none of its events go unheard.
        await followHost()
        Task { [plugins, pluginEvents] in
            for await event in pluginEvents {
                markUnread(after: event)
                keepClearedConversation(after: event)
                await plugins.broadcast(event)
            }
        }
        Task { [titleEvents] in
            for await event in titleEvents {
                await workspaceGotTitle(event)
            }
        }
        Task { await resumeWorkspaceRestores() }
        watchRemovedWorkspaces()
        // The runtimes made at init for agents with saved sessions, which start with the rest.
        let early = runtimes.all
        observeAgents()
        parkAgentsWhenIdle()
        await syncAgents(alsoStarting: early)
        if runsAgentsInHost {
            Task { await openWorkingHostSessions() }
        }
    }

    func restart(_ agent: AgentDefinition.ID) async {
        guard !runsAgentsInHost else { return await restartOnHost(agent) }
        sessions.removeAll(of: agent)
        guard let runtime = runtimes.replace(agent) else { return }
        await start(runtime, environment: await launchEnvironment(refresh: true))
        // The selected session's model went with the old process; replay it from the new one.
        if let selection, selection.agent == agent {
            await loadSession(selection)
        }
    }

    /// The user's login-shell environment, which agents launch with. Features that run the user's
    /// own tools (git, gh) use it too, since an app launched from the Finder has a bare PATH.
    func shellEnvironment(refresh: Bool = false) async -> [String: String] {
        await environment.current(refresh: refresh)
    }

    /// The environment agents launch with, once plugins have what launches depend on
    /// (`NativePlugin.prepareForLaunch`). Internal only for the AppModel+ extensions.
    func launchEnvironment(refresh: Bool = false) async -> [String: String] {
        async let shell = environment.current(refresh: refresh)
        await plugins.prepareForLaunch()
        return await shell
    }

    /// Signs in to `agent`, reporting whether that worked.
    @discardableResult
    func signIn(to agent: AgentDefinition.ID, with method: AuthMethod, thenStartSession: Bool = false) async -> Bool {
        guard let runtime = runtimes[agent] else { return false }
        // Some agents only sign in from a terminal; the sign-in sheet takes it from here.
        if let request = AgentTerminalSignIn(agent: runtime.agent, method: method, startsSession: thenStartSession) {
            terminalSignIn = request
            return false
        }
        guard await ensureRunning(agent) != nil else {
            actionFailure = ActionFailure("Couldn't Sign In to \(runtime.agent.displayName)", startFailure(of: agent))
            return false
        }
        do {
            try await runtime.signIn(with: method)
        } catch {
            actionFailure = ActionFailure(
                "Couldn't Sign In to \(runtime.agent.displayName)", error.localizedDescription)
            return false
        }
        await refreshSessions(of: runtime)
        return true
    }

    /// Looks for agents again after the user installed one or signed in from a terminal, with a
    /// fresh login-shell environment, and starts the ones now installed. Returns those.
    @discardableResult
    func checkForAgents() async -> [AgentDefinition] {
        let missing = Set(agentsToAdd.map(\.id))
        _ = await environment.current(refresh: true)
        AgentIconStore.shared.reset()
        // The host reads the login shell itself; it reads it again too.
        await syncHostAgents(refreshEnvironment: true)
        await syncAgents()
        return plugins.agents.filter { missing.contains($0.id) && installations.isInstalled($0.id) }
    }

    private func observeAgents() {
        withObservationTracking {
            _ = plugins.agents
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeAgents()
                await self?.syncAgents()
            }
        }
    }

    /// Creates and removes runtimes as plugins and installations say, and starts the new ones (and
    /// `alsoStarting`, ones made earlier) that are worth starting.
    private func syncAgents(alsoStarting earlier: [AgentRuntime] = []) async {
        let environment = await launchEnvironment()
        installations.check(plugins.agents, environment: environment)
        let (added, removed) = runtimes.sync(including: installations.isInstalled)
        // The host launches agents from what it was last told; it hears plugins' changes first.
        await syncHostAgents()
        let worthStarting = agentsWorthStarting()
        if !hasCheckedAgents {
            hasCheckedAgents = true
            agentCheckWaiters.forEach { $0.resume() }
            agentCheckWaiters = []
        }
        for agent in removed {
            sessions.removeAll(of: agent)
            catalog.remove(agent: agent)
            problems.resolveAll { $0.work == .listing(agent) }
            if selection?.agent == agent {
                selection = nil
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for runtime in added + earlier
            where runtimes[runtime.agent.id] === runtime && runtime.status == .idle
                && worthStarting.contains(runtime.agent.id)
            {
                group.addTask { await self.start(runtime, environment: environment) }
            }
        }
    }

    /// Launches an agent and routes its events. Internal only for AppModel+Recovery.swift.
    func start(_ runtime: AgentRuntime, environment: [String: String]) async {
        let agent = runtime.agent.id
        // Plugins' policy for every session of the agent, in the agent's terms (AppModel+LaunchPolicy.swift).
        runtime.launchPolicyEnvironment = plugins.launchEnvironment(for: agent)
        await runtime.start(environment: environment.merging(runtime.launchPolicyEnvironment) { $1 }) {
            [weak self] event in
            guard let self else { return }
            if case .disconnected = event {
                handleCrash(of: agent)
            } else {
                sessions.handle(event, from: agent, connection: runtimes[agent]?.localConnection)
            }
        }
        if case .failed = runtime.status {
            post(.failed(nil, reason: "\(runtime.agent.displayName) couldn't start"))
        }
        // Not awaited: whoever started the agent wants it for a session, not for the listing.
        Task { await refreshSessions(of: runtime) }
    }

    /// Tells plugins about something outside a session's own events. Internal for the extensions.
    func post(_ event: SessionEvent) {
        services.post(event)
    }

    // MARK: - Sessions

    func session(_ key: SessionKey) -> SessionModel? {
        sessions.session(key)
    }

    /// Looks a session up by Native's own id for it, for plugins that key resources by that.
    func session(clientID: UUID) -> SessionModel? {
        sessions.session(clientID: clientID)
    }

    /// Looks a session up by the agent's id for it, whichever agent that is, for places that only
    /// have the id (another session's name in a transcript).
    func session(id: SessionID) -> SessionModel? {
        sessions.session(id: id)
    }

    /// Starts a fresh session in an empty one's place, for one the agent never saved (it had no turn
    /// yet) and so can't reopen. Internal only for AppModel+Recovery.swift.
    func replaceEmptySession(_ old: SessionModel, on runtime: AgentRuntime) async -> SessionModel? {
        let project = catalog.lookup(old.key)?.project
        guard let session = try? await launcher.start(on: runtime, cwd: old.cwd, project: project, continuing: old)
        else { return nil }
        await session.adoptConfigChoices(of: old)
        session.draft = old.draft
        catalog.swap(old.key, for: SessionInfo(sessionId: session.id, cwd: old.cwd.folderPath, updatedAt: .now))
        if selection == old.key {
            selection = session.key
        }
        return session
    }

    /// Opens a listed session, replaying its history from the agent the first time, which starts
    /// the agent if it isn't running. When it fails before the session has a model, `openFailures`
    /// says why; an agent that won't start says so through its status instead.
    func loadSession(_ key: SessionKey) async {
        guard sessions.session(key) == nil, let info = catalog.lookup(key)?.info else { return }
        openFailures[key] = nil
        guard let runtime = await ensureRunning(key.agent) else {
            if runtimes[key.agent] == nil {
                openFailures[key] = SessionOpenFailure(.agentMissing, agent: key.agent.rawValue)
            }
            return
        }
        // Selecting a row loads it from two places; the first one to get here opens it.
        guard sessions.session(key) == nil else { return }
        do {
            _ = try await launcher.load(
                key, cwd: URL(filePath: info.cwd, directoryHint: .isDirectory), title: info.title, on: runtime)
        } catch {
            guard sessions.session(key) == nil else { return }
            openFailures[key] = SessionOpenFailure(error, agent: runtime.agent.displayName)
        }
    }
}
