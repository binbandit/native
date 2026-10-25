import ACP
import Foundation

// New sessions the user starts. The click lists a starting task and selects it at once, so there's
// a row and a composer while the workspace is made (a worktree of a large repository takes a while
// to check out) and the agent starts, both at the same time. Then the agent opens the session and
// it takes the task's place. What fails stays on the task, with Retry and Discard.
extension AppModel {
    /// Whether a new session is under way.
    var isCreatingSession: Bool {
        startingTasks.contains { $0.failure == nil }
    }

    /// The agent the newest new session under way starts with, for the agent cards on Home.
    var creatingSessionWith: AgentDefinition.ID? {
        startingTasks.first { $0.failure == nil }?.agent.id
    }

    func startingTask(_ key: SessionKey) -> StartingTask? {
        startingTasks.first { $0.id == key }
    }

    func startingTasks(in project: Project.ID) -> [StartingTask] {
        startingTasks.filter { $0.project == project }
    }

    /// Starts a session in `project` with `agent`, defaulting to the current project and its
    /// default agent. Returns once the session is open, or the starting task says why it isn't.
    func newSession(in project: Project.ID? = nil, with agent: AgentDefinition.ID? = nil) async {
        guard let project = project.flatMap(projects.project) ?? currentProject else {
            isAddingProject = true
            return
        }
        // On the paired host this project's tasks last started on, while it can take one.
        if case .remote = preferredDevice(for: project.id) {
            return await newSession(in: project.id, with: agent, on: preferredDevice(for: project.id))
        }
        // A task can't start in a folder that's gone. The project already says so, with Retry, so show
        // it rather than an alert about git; looking again first lets a folder that's back through.
        checkFolder(of: project)
        guard missingFolder(of: project.id) == nil else {
            focusProject(project.id)
            return
        }
        // Right after launch there may be no default agent yet, until the check for agents is done.
        if agent ?? defaultAgent(in: project)?.id == nil {
            await agentsChecked()
        }
        if agent == nil, agentStartupFailure != nil {
            focusProject(project.id)
            isChoosingAgent = true
            return
        }
        let isAgentPicked = agent != nil
        guard let agent = agent ?? defaultAgent(in: project)?.id else {
            // No agent is installed; Add Agent says how to get one.
            isAddingAgent = true
            return
        }
        guard let definition = runtimes[agent]?.agent else {
            actionFailure = ActionFailure("Couldn't Start a Task", startFailure(of: agent))
            return
        }
        // After a sign-in, the task that waited for it carries on instead of a second one starting.
        if let waiting = startingTasks.first(where: { $0.agent.id == agent && $0.failure?.needsSignIn == true }) {
            selection = waiting.id
            await start(waiting)
            return
        }
        let task = StartingTask(
            project: project.id, agent: definition, isAgentPicked: isAgentPicked,
            workspaceLabel: taskWorkspaces?.newTaskWorkspaceLabel(in: project) ?? "Preparing the workspace")
        startingTasks.insert(task, at: 0)
        selection = task.id
        await start(task)
    }

    /// Tries a task that failed to start again, keeping its draft and the workspace already made.
    func retry(_ task: StartingTask) async {
        guard let failure = task.failure else { return }
        if failure.needsRestart, runtimes[task.agent.id]?.status.canRetry == true {
            task.failure = nil
            task.isAgentReady = false
            await restart(task.agent.id)
            guard !task.isDiscarded else { return }
        }
        await start(task)
    }

    /// Starts a task that couldn't get a worktree in the project's own folder instead.
    func startInProjectFolder(_ task: StartingTask) async {
        guard task.failure?.canUseProjectFolder == true, let project = projects.project(task.project) else { return }
        task.folder = project.url
        await start(task)
    }

    /// Gives up on a starting task. A workspace already made for it is removed; one still being
    /// made is removed once it's done.
    func discard(_ task: StartingTask) {
        task.isDiscarded = true
        remove(task)
        removeWorkspace(of: task)
    }

    func start(_ task: StartingTask) async {
        // A task on a paired host is made there (AppModel+HostsStarting.swift).
        if case .remote(let host) = task.device { return await start(task, on: host) }
        guard let project = projects.project(task.project) else { return remove(task) }
        task.failure = nil
        let agent = task.agent.id
        async let runtime = readyRuntime(for: task)
        async let workspace = prepareWorkspace(for: task, in: project)
        let ready = await runtime
        let folder: URL
        do {
            folder = try await workspace
        } catch TaskWorkspaceError.noCommits {
            task.failure = StartingTask.Failure(
                title: "This repository has no commits yet",
                message:
                    "A worktree starts from a commit, so there's nothing to make one from. Start the task in the project folder, or make a first commit and retry.",
                canUseProjectFolder: true)
            return
        } catch {
            fail(task, "Couldn't create the task's workspace", error.localizedDescription.withoutTerminalEscapes)
            return
        }
        guard !task.isDiscarded else { return removeWorkspace(of: task) }
        guard let ready else {
            fail(task, "Couldn't start \(task.agent.displayName)", startFailure(of: agent))
            if case .failed = runtimes[agent]?.status {
                task.failure?.needsRestart = true
            }
            return
        }
        do {
            let session = try await launcher.start(on: ready, cwd: folder, project: project.id)
            guard !task.isDiscarded else {
                sessions.remove(session)
                return removeWorkspace(of: task)
            }
            catalog.add(
                SessionInfo(sessionId: session.id, cwd: folder.folderPath, updatedAt: .now), for: agent, in: project.id)
            unsentSessions.started(session.key)
            finish(task, with: session)
        } catch {
            if ready.noteSignInRequired(by: error), !ready.authMethods.isEmpty {
                signInPrompt = agent
                fail(
                    task, "\(task.agent.displayName) needs you to sign in",
                    "Sign in, and the task starts with what you've written.", needsSignIn: true)
            } else {
                fail(
                    task, "Couldn't start a \(task.agent.displayName) task",
                    error.localizedDescription.withoutTerminalEscapes)
            }
        }
    }

    /// Waits for the task's agent, starting it if it's idle.
    private func readyRuntime(for task: StartingTask) async -> AgentRuntime? {
        let runtime = await ensureRunning(task.agent.id)
        task.isAgentReady = runtime != nil
        return runtime
    }

    /// The task's folder: the one made on an earlier try, or a new one from the provider. The
    /// project's git work runs one task at a time, since git locks its config and index while it
    /// writes them.
    private func prepareWorkspace(for task: StartingTask, in project: Project) async throws -> URL {
        if let folder = task.folder { return folder }
        let previous = workspacePreparations[project.id]
        let work = Task { [taskWorkspaces] in
            await previous?.value
            return try await taskWorkspaces?.workspace(forNewTaskIn: project, title: nil) ?? project.url
        }
        workspacePreparations[project.id] = Task { _ = try? await work.value }
        let folder = try await work.value
        task.folder = folder
        return folder
    }

    /// The session takes the task's place: in the sidebar, the selection and history, with the draft.
    /// Internal only for AppModel+HostsStarting.swift, as are `fail` and `remove`.
    func finish(_ task: StartingTask, with session: SessionModel) {
        task.openedSession = session.key
        session.draft = task.draft
        let wasSelected = selection == task.id
        startingTasks.removeAll { $0 === task }
        history.replace(task.id, with: session.key)
        if wasSelected {
            session.wantsComposerFocus = !task.isSendRequested
            selection = session.key
        }
        // The project's agent is the project's choice, not the user's pick for every project.
        if task.isAgentPicked {
            rememberLastUsed(task.agent.id)
        }
        if task.isSendRequested {
            Task { await session.submit(.queue) }
        }
    }

    func fail(_ task: StartingTask, _ title: String, _ message: String, needsSignIn: Bool = false) {
        task.failure = StartingTask.Failure(title: title, message: message, needsSignIn: needsSignIn)
    }

    func remove(_ task: StartingTask) {
        startingTasks.removeAll { $0 === task }
        if selection == task.id {
            focusProject(task.project)
        }
    }

    /// Removes the workspace made for a discarded task, unless it's the project's own folder.
    func removeWorkspace(of task: StartingTask) {
        guard let route = taskActionRoute(for: task), let folder = route.folder else { return }
        task.folder = nil
        Task {
            do {
                try await deleteWorkspace(using: route)
            } catch {
                problems.report(
                    ProjectProblem(
                        project: route.project.id, work: .workspaceDeletion(task.id, folder: folder),
                        title: "Couldn't remove a discarded task's workspace",
                        recovery: "The task is gone, but its workspace is still on disk.",
                        details: error.localizedDescription))
            }
        }
    }
}
