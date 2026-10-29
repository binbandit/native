import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeLink

// New sessions on a paired host. They start like this Mac's (AppModel+StartingTasks.swift): the
// click lists a starting task at once, with its composer, while the host's checkout is made (cloned
// when it has none) and its agent starts; then the session takes the task's place. What fails stays
// on the task, with Retry and Discard.
extension AppModel {
    /// Starts a session in `project` on `device` with `agent`, each defaulting as New Session does.
    /// This Mac goes the usual way (`newSession(in:with:)`); a paired host runs the session in the
    /// project's checkout there, cloning the project first when it has none.
    func newSession(
        in project: Project.ID? = nil, with agent: AgentDefinition.ID? = nil, on device: SessionDevice,
        draft: String = ""
    ) async {
        let project = project.flatMap(projects.project) ?? currentProject ?? NoProjectLocation.group
        if project.isNoProject, device.isRemote {
            actionFailure = ActionFailure(
                "Choose a Project", "Tasks without a project run on this Mac. Choose a project to use another device.")
            return
        }
        guard case .remote(let hostID) = device else {
            // Remembered first, so New Session here doesn't send it back to the host used last.
            ProjectDevicePreference.remember(.thisMac, for: project.id)
            await newSession(in: project.id, with: agent)
            if !draft.isEmpty, let selection, let session = session(selection), session.draft.isEmpty {
                session.draft = draft
            }
            return
        }
        let title = "Couldn't Start a Task"
        guard let host = hosts.host(hostID) else {
            actionFailure = ActionFailure(title, "That host isn't paired with this Mac anymore.")
            return
        }
        guard let option = deviceOptions(for: project.id).first(where: { $0.device == device }), option.canStart
        else {
            let reason = deviceOptions(for: project.id).first { $0.device == device }?.unavailableReason
            actionFailure = ActionFailure(title, reason ?? "\(host.name) can't take a task right now.")
            return
        }
        let agentID = agent ?? defaultAgent(in: project)?.id
        guard let runtime = agentID.flatMap(host.runtime) ?? host.runtimes.first(where: \.isAvailable) else {
            actionFailure = ActionFailure(title, "\(host.name) has no agent that can start a task.")
            return
        }
        ProjectDevicePreference.remember(device, for: project.id)
        let label =
            option.hasCheckout
            ? "\(taskWorkspaces?.newTaskWorkspaceLabel(in: project) ?? "Getting ready") on \(host.name)"
            : "Cloning \(project.name) onto \(host.name)"
        let task = StartingTask(
            project: project.id, agent: runtime.agent, isAgentPicked: agent != nil, workspaceLabel: label)
        task.device = device
        task.workspaceChoice = preferredTaskWorkspace(in: project.id)
        if task.workspaceChoice == .project { task.workspaceLabel = "Using the project folder on \(host.name)" }
        task.draft = draft
        startingTasks.insert(task, at: 0)
        selection = task.id
        await start(task, on: hostID)
    }

    /// Moves a new task that hasn't had a message yet to another device, for the device picker:
    /// it starts there with what's in its composer, and the empty one here goes. A task that has
    /// had a message stays where it is: its conversation lives on its host.
    func moveNewTask(_ key: SessionKey, to device: SessionDevice) async {
        guard device != self.device(of: key) else { return }
        let task = startingTask(key)
        let session = session(key)
        guard let project = task?.project ?? catalog.lookup(key)?.project,
            task != nil || (session.map { $0.canChangeWorkspace } ?? false)
        else { return }
        let agent = (task?.agent ?? session?.agent)?.id
        let draft = task?.draft ?? session?.draft ?? ""
        if let task {
            discard(task)
        } else if let session {
            discardUnsent(session)
        }
        await newSession(in: project, with: agent, on: device, draft: draft)
    }

    /// Lets go of a new session that never had a message: nothing of it is worth keeping, so it
    /// leaves the sidebar and its host closes it.
    private func discardUnsent(_ session: SessionModel) {
        sessions.remove(session)
        catalog.remove(session.key)
        unsentSessions.forget(session.key)
        if let link = session.host {
            Task { try? await link.client.closeSession(link.id, closeInAgent: true) }
        }
    }

    /// Makes a starting task's session on a paired host: its checkout (cloned if it has none), its
    /// agent, then the session. Internal only for AppModel+StartingTasks.swift, whose `retry` comes
    /// back here.
    func start(_ task: StartingTask, on hostID: RemoteHostID) async {
        guard let project = projects.project(task.project) else { return remove(task) }
        task.failure = nil
        guard let host = hosts.host(hostID) else {
            return fail(task, "That host isn't paired anymore", "Pair it again in Settings ▸ Hosts, then retry.")
        }
        guard host.isOnline else {
            return fail(
                task, "Couldn't reach \(host.name)",
                host.availability.reason ?? "Native keeps trying; retry once it's connected.")
        }
        guard let runtime = host.runtime(task.agent.id) else {
            return fail(task, "\(host.name) doesn't run \(task.agent.displayName)", "Pick another agent, then retry.")
        }
        // The agent starts while the checkout is made.
        let starting = Task { if !runtime.isReady { await runtime.startOnHost() } }
        let folder: String
        do {
            folder = try await checkoutFolder(for: task, of: project, on: host)
        } catch {
            await starting.value
            return fail(task, "Couldn't get \(project.name) onto \(host.name)", error.localizedDescription)
        }
        await starting.value
        task.isAgentReady = runtime.isReady
        guard !task.isDiscarded else { return removeWorkspace(of: task) }
        guard runtime.isReady else {
            return fail(
                task, "Couldn't start \(task.agent.displayName) on \(host.name)",
                runtime.status.problemDescription ?? "It didn't start.")
        }
        do {
            let session = try await launcher.start(
                on: runtime, cwd: URL(filePath: folder, directoryHint: .isDirectory), project: project.id)
            guard !task.isDiscarded else {
                sessions.remove(session)
                return removeWorkspace(of: task)
            }
            await applyComposeChoices(of: task, to: session)
            guard !task.isDiscarded else { sessions.remove(session); return removeWorkspace(of: task) }
            rememberRemoteWorkspace(of: session, in: project)
            indexRemoteSessions()
            finish(task, with: session)
        } catch {
            if runtime.noteSignInRequired(by: error) {
                fail(
                    task, "\(task.agent.displayName) needs you to sign in on \(host.name)",
                    "Sign in from Settings ▸ Hosts, and retry: the task keeps what you've written.", needsSignIn: true)
            } else {
                fail(
                    task, "Couldn't start a \(task.agent.displayName) task on \(host.name)",
                    ((error as? RPCError)?.detail ?? error.localizedDescription).withoutTerminalEscapes)
            }
        }
    }

    /// The folder the task runs in on the host: a worktree of the project's checkout there, as on
    /// this Mac (the Git settings say worktree or branch), with the checkout cloned first when the
    /// host has none. A retry reuses what an earlier try made.
    private func checkoutFolder(
        for task: StartingTask, of project: Project, on host: RemoteHost
    ) async throws
        -> String
    {
        if let folder = task.folder { return folder.folderPath }
        let previous = workspacePreparations[project.id]
        let work = Task {
            await previous?.value
            var path = project.checkoutPath(on: .remote(host.id))
            if path == nil {
                path = try await cloneProject(project.id, onto: host)
            }
            guard let path else { throw RemoteCheckoutError.noFolder(host.name) }
            let prepared: TaskWorkspacePreparation =
                if let workspaces = await taskWorkspaces(on: host) {
                    if let choice = task.workspaceChoice {
                        try await workspaces.prepareWorkspace(for: choice, in: project.onHost(at: path))
                    } else {
                        .init(
                            folder: try await workspaces.workspace(forNewTaskIn: project.onHost(at: path), title: nil),
                            createdForTask: true)
                    }
                } else {
                    // A host that can't run commands for this Mac still runs agents: in its checkout.
                    .init(folder: URL(filePath: path, directoryHint: .isDirectory), createdForTask: false)
                }
            task.folder = prepared.folder
            task.ownsWorkspace = prepared.createdForTask && !SessionFolder.isSame(prepared.folder.folderPath, path)
            return prepared.folder.folderPath
        }
        workspacePreparations[project.id] = Task { _ = try? await work.value }
        return try await work.value
    }
}

extension AgentRuntimeStatus {
    /// What went wrong, for a failed or missing agent.
    fileprivate var problemDescription: String? {
        switch self {
        case .failed(let problem): problem
        case .notInstalled(let command): "\(command) isn't installed on that host."
        default: nil
        }
    }
}
