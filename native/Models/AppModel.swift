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
    /// Makes and removes the folders tasks run in (worktrees). Set by the app from the Git feature;
    /// without it tasks run in the project folder.
    weak var taskWorkspaces: (any TaskWorkspaceProvider)?
    /// The latest action the user can take back, for the window's undo toast.
    var lastUndoable: UndoableAction?

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
    /// An agent that wants the user to sign in before it starts a session.
    var signInPrompt: AgentDefinition.ID?
    var errorMessage: String?
    /// The agent a session is being created with, while that's under way.
    private(set) var creatingSessionWith: AgentDefinition.ID?
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
    @ObservationIgnored var archivedWorkspaces: [SessionKey: TaskWorkspaceRemoval] = [:]
    @ObservationIgnored let deletedSessions = DeletedSessions()
    var history = NavigationHistory<SessionKey>()
    @ObservationIgnored var isNavigatingHistory = false

    private var lastUsedAgent: AgentDefinition.ID?
    /// Internal only for AppModel+Recovery.swift.
    @ObservationIgnored var restartPolicies: [AgentDefinition.ID: AgentRestartPolicy] = [:]
    @ObservationIgnored private let services: SessionServices
    @ObservationIgnored private let launcher: SessionLauncher
    /// Internal only for AppModel+Listing.swift.
    @ObservationIgnored let taskRecords = TaskSessionRecords()
    @ObservationIgnored private let environment = ShellEnvironment()
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
    @ObservationIgnored private var isStarted = false

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
        services = SessionServices(plugins: plugins, titles: titles) { continuation.yield($0) } titleLanded: { key, folder, title in
            titleContinuation.yield(TitleEvent(key: key, folder: folder, title: title))
        }
        runtimes = AgentRuntimes(plugins: plugins)
        projects = Projects()
        catalog = SessionCatalog()
        ordering = SessionOrdering()
        sessions = SessionStore(services: services)
        unread = UnreadSessions()
        launcher = SessionLauncher(plugins: plugins, services: services, store: sessions)
        lastUsedAgent = UserDefaults.standard.string(forKey: Self.lastUsedAgentKey).map(AgentDefinition.ID.init(rawValue:))
    }

    /// Ends every agent's process, for when the app quits.
    func stopAgents() {
        runtimes.stopAll()
    }

    // MARK: - Agents

    /// The agents' runtimes, in plugin order.
    var agents: [AgentRuntime] {
        runtimes.all
    }

    func runtime(_ agent: AgentDefinition.ID) -> AgentRuntime? {
        runtimes[agent]
    }

    /// The agent new sessions start with unless the user picks another: the one used last, or
    /// while that one can't start sessions, the first that can.
    var defaultAgent: AgentDefinition? {
        let lastUsed = agents.first { $0.agent.id == lastUsedAgent }
        if let lastUsed, lastUsed.isReady { return lastUsed.agent }
        return (agents.first(where: \.isReady) ?? lastUsed ?? agents.first)?.agent
    }

    /// Starts every agent plugins provide, and keeps up as plugins come and go.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        Task { [plugins, pluginEvents] in
            for await event in pluginEvents {
                markUnread(after: event)
                await plugins.broadcast(event)
            }
        }
        Task { [titleEvents] in
            for await event in titleEvents {
                await workspaceGotTitle(event)
            }
        }
        observeAgents()
        await syncAgents()
    }

    func restart(_ agent: AgentDefinition.ID) async {
        sessions.removeAll(of: agent)
        guard let runtime = runtimes.replace(agent) else { return }
        await start(runtime, environment: await environment.current(refresh: true))
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

    /// Signs in to `agent`, reporting whether that worked.
    @discardableResult
    func signIn(to agent: AgentDefinition.ID, with method: AuthMethod) async -> Bool {
        guard let runtime = runtimes[agent] else { return false }
        do {
            try await runtime.signIn(with: method)
        } catch {
            errorMessage = "Couldn't sign in to \(runtime.agent.displayName): \(error.localizedDescription)"
            return false
        }
        await refreshSessions(of: runtime)
        return true
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

    private func syncAgents() async {
        let (added, removed) = runtimes.sync()
        for agent in removed {
            sessions.removeAll(of: agent)
            catalog.remove(agent: agent)
            if selection?.agent == agent {
                selection = nil
            }
        }
        let environment = await self.environment.current()
        await withTaskGroup(of: Void.self) { group in
            for runtime in added {
                group.addTask { await self.start(runtime, environment: environment) }
            }
        }
    }

    /// Launches an agent and routes its events. Internal only for AppModel+Recovery.swift.
    func start(_ runtime: AgentRuntime, environment: [String: String]) async {
        let agent = runtime.agent.id
        await runtime.start(environment: environment) { [weak self] event in
            guard let self else { return }
            if case .disconnected = event {
                handleCrash(of: agent)
            } else {
                sessions.handle(event, from: agent, connection: runtimes[agent]?.connection)
            }
        }
        await refreshSessions(of: runtime)
    }

    // MARK: - Sessions

    /// A project's sessions from every agent, in the user's order, then most recently active first.
    func sessions(in project: Project.ID) -> [SessionSummary] {
        let summaries = allSessions(in: project).filter { summary in
            !archivedSessions.contains(summary.id) && !pendingDeletionKeys.contains(summary.id) && !ordering.isPinned(summary.id)
        }
        return ordering.sorted(summaries, in: project, recency: lastActive)
    }

    /// A project's sessions from every agent, archived ones included.
    func allSessions(in project: Project.ID) -> [SessionSummary] {
        agents.flatMap { runtime in
            catalog.sessions(in: project, of: runtime.agent.id).map { SessionSummary(project: project, agent: runtime.agent, info: $0) }
        }
    }

    /// Every session in the sidebar, in its order: pinned first, then each project's.
    var sessionList: [SessionSummary] {
        pinnedSessions + projects.all.flatMap { sessions(in: $0.id) }
    }

    func moveSessions(in project: Project.ID, fromOffsets source: IndexSet, toOffset destination: Int) {
        ordering.move(sessions(in: project).map(\.id), in: project, fromOffsets: source, toOffset: destination)
    }

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


    var isCreatingSession: Bool {
        creatingSessionWith != nil
    }

    /// Whether a session can start now in `project` with `agent`, defaulting to the current project
    /// and the default agent.
    func canCreateSession(in project: Project.ID? = nil, with agent: AgentDefinition.ID? = nil) -> Bool {
        guard let agent = agent ?? defaultAgent?.id, (project ?? currentProject?.id) != nil else { return false }
        return !isCreatingSession && runtimes[agent]?.isReady == true
    }

    private func lastActive(_ summary: SessionSummary) -> Date {
        sessions.session(summary.id)?.lastActivity ?? summary.info.updatedDate ?? .distantPast
    }

    /// Starts a session in `project` with `agent`, defaulting to the current project and the
    /// default agent.
    func newSession(in project: Project.ID? = nil, with agent: AgentDefinition.ID? = nil) async {
        guard let project = project.flatMap(projects.project) ?? currentProject else {
            isAddingProject = true
            return
        }
        guard let agent = agent ?? defaultAgent?.id,
              canCreateSession(in: project.id, with: agent),
              let runtime = runtimes[agent]
        else { return }
        creatingSessionWith = agent
        defer { creatingSessionWith = nil }
        do {
            let cwd = try await taskWorkspaces?.workspace(forNewTaskIn: project, title: nil) ?? project.url
            let session = try await launcher.start(on: runtime, cwd: cwd)
            catalog.add(SessionInfo(sessionId: session.id, cwd: cwd.folderPath, updatedAt: .now), for: agent, in: project.id)
            session.wantsComposerFocus = true
            selection = session.key
            lastUsedAgent = agent
            UserDefaults.standard.set(agent.rawValue, forKey: Self.lastUsedAgentKey)
        } catch {
            if runtime.noteSignInRequired(by: error), !runtime.authMethods.isEmpty {
                signInPrompt = agent
            } else {
                errorMessage = "Couldn't start a \(runtime.agent.displayName) session: \(error.localizedDescription)"
            }
        }
    }

    /// Starts a session for Native's tools, out of the sidebar: one another session delegates work
    /// to (`parent`, Native's id for it; the session is its subagent and works in its folder unless
    /// `cwd` says otherwise), or a detached one such as a workflow step. Returned idle.
    func startTaskSession(agent: AgentDefinition.ID, cwd: URL? = nil, parent: UUID? = nil) async throws -> SessionModel {
        let parentSession = try parent.map { id in
            guard let session = sessions.session(clientID: id) else { throw SessionLauncher.LaunchError.parentClosed }
            return session
        }
        guard let runtime = runtimes[agent], runtime.isReady else {
            throw SessionLauncher.LaunchError.agentUnavailable(runtimes[agent]?.agent.displayName ?? agent.rawValue)
        }
        guard let cwd = cwd ?? parentSession?.cwd ?? currentProject?.url else {
            throw SessionLauncher.LaunchError.failed(agent: runtime.agent.displayName, underlying: CocoaError(.fileNoSuchFile))
        }
        do {
            let session = try await launcher.start(on: runtime, cwd: cwd, origin: .task, parent: parentSession)
            taskRecords.add(TaskSessionRecords.Record(key: session.key, cwd: cwd, parent: parentSession?.key))
            return session
        } catch {
            runtime.noteSignInRequired(by: error)
            throw SessionLauncher.LaunchError.failed(agent: runtime.agent.displayName, underlying: error)
        }
    }

    /// Reopens a task session Native started, in this run or an earlier one, replaying its history
    /// and keeping it out of the sidebar. A delegated one rejoins its parent when that's open.
    /// Returns the open session if it already is.
    func reopenTaskSession(agent: AgentDefinition.ID, id: SessionID, cwd: URL) async throws -> SessionModel {
        let key = SessionKey(agent: agent, id: id)
        if let session = sessions.session(key) {
            return session
        }
        guard let runtime = runtimes[agent], runtime.isReady else {
            throw SessionLauncher.LaunchError.agentUnavailable(runtimes[agent]?.agent.displayName ?? agent.rawValue)
        }
        let record = taskRecords.record(key)
        let parent = record?.parent.flatMap(sessions.session)
        let session = try await launcher.load(key, cwd: cwd, on: runtime, origin: .task, parent: parent)
        taskRecords.add(TaskSessionRecords.Record(key: key, cwd: cwd, parent: record?.parent))
        return session
    }

    /// Starts a fresh session in an empty one's place, for one the agent never saved (it had no turn
    /// yet) and so can't reopen. Internal only for AppModel+Recovery.swift.
    func replaceEmptySession(_ old: SessionModel, on runtime: AgentRuntime) async -> SessionModel? {
        guard let session = try? await launcher.start(on: runtime, cwd: old.cwd) else { return nil }
        session.draft = old.draft
        catalog.swap(old.key, for: SessionInfo(sessionId: session.id, cwd: old.cwd.folderPath, updatedAt: .now))
        if selection == old.key {
            selection = session.key
        }
        return session
    }

    /// Opens a listed session, replaying its history from the agent the first time.
    func loadSession(_ key: SessionKey) async {
        guard sessions.session(key) == nil, let runtime = runtimes[key.agent], let info = catalog.lookup(key)?.info else { return }
        _ = try? await launcher.load(key, cwd: URL(filePath: info.cwd, directoryHint: .isDirectory), title: info.title, on: runtime)
    }
}
