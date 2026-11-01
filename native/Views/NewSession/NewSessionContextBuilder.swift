import ACP
import Foundation
import Git
import GitHub
import ProjectActions
import TaskScripts

/// Builds a new session's `NewSessionContext` from what the app already holds: the project and its
/// tasks, git's status of the task's folder and the project's checkout, the GitHub inbox and the
/// project's actions. Nothing here runs git or gh; the view asks for this on every update, so it
/// only reads.
@MainActor
struct NewSessionContextBuilder {
    let session: SessionModel
    let project: Project
    let model: AppModel
    let git: GitStore
    let gitHub: GitHubModel
    let runner: ProjectActionRunner
    let scripts: TaskScriptCenter
    let settings: SettingsPresentation
    /// The project's repositories on GitHub, lowercased `owner/name`, once its remotes are read.
    let repositories: [String]

    func context() -> NewSessionContext {
        let path = project.checkoutPath(on: model.device(of: session.key)) ?? project.path
        let checkout = git.model(for: URL(filePath: path), session: session.key)
        return NewSessionContext(
            projectName: project.name,
            projectIcon: ProjectIconStore.shared.icon(for: project, size: NewSessionMetrics.titleIcon),
            workspace: workspace(checkout: checkout),
            checkoutChanges: checkout.status?.changedFileCount ?? 0,
            tasks: tasks,
            pullRequests: pullRequests,
            actions: actions,
            draft: { [session] text in
                session.draft = text
                session.wantsComposerFocus = true
            },
            editActions: { [runner, settings, project] in
                if runner.store.list(for: project).all.isEmpty {
                    runner.store.requestNewAction(in: project)
                }
                settings.open(.project(project.id))
            },
            device: device,
            changeWorkspace: session.canChangeWorkspace ? { [session] in session.requestWorkspaceChange() } : nil,
            chooseWorkspace: session.canChangeWorkspace && model.offersProjectFolderTasks
                ? { choice in
                    _ = try await model.changeWorkspace(of: session, to: choice)
                } : nil,
            sharedFolderNote: model.projectFolderNote(
                in: project.id, on: model.device(of: session.key), excluding: session.key),
            canCreateSeparateFolder: checkout.state == .ready && checkout.branch?.isUnborn == false
        )
    }

    /// Where the task runs, once a host is paired: choosing another device moves the task there,
    /// with its draft, while it has had no message.
    private var device: NewSessionContext.Device? {
        guard model.offersRemoteHosts, !model.hosts.all.isEmpty else { return nil }
        let key = session.key
        return NewSessionContext.Device(
            options: model.deviceOptions(for: project.id), selection: model.device(of: key)
        ) { [model] device in
            Task { await model.moveNewTask(key, to: device) }
        }
    }

    private func workspace(checkout: GitRepositoryModel) -> NewSessionContext.Workspace {
        let folder = git.model(for: session.cwd, session: session.key)
        switch folder.state {
        case .loading, .failed:
            return .unknown(path: session.cwd.abbreviatedPath)
        case .notRepository:
            return .folder(path: session.cwd.abbreviatedPath)
        case .ready:
            let branch = folder.branch?.name
            guard !model.usesProjectFolder(session.key) else { return .checkout(branch: branch) }
            // The branch the worktree was made from, as its setup recorded it; else what the project's
            // checkout is on, which it was made from a moment ago.
            let base = scripts.setupRun(in: session.cwd)?.context.baseBranch ?? checkout.branch?.name
            return .worktree(branch: branch ?? folder.branch?.displayName ?? "", base: base)
        }
    }

    private var tasks: [NewSessionContext.RecentTask] {
        model.sessions(in: project.id)
            .filter { $0.id != session.key && hasWork($0) }
            .map { summary in
                let live = model.session(summary.id)
                return NewSessionContext.RecentTask(
                    id: "\(summary.id.agent.rawValue)/\(summary.id.id.rawValue)",
                    title: model.title(for: summary),
                    agentName: summary.agent.displayName,
                    status: status(of: live),
                    date: model.lastActivity(for: summary),
                    open: { [model] in model.selection = summary.id }
                )
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Whether a task has anything to go back to: a conversation, for one open in this run, or a
    /// title, which the agent or the user only gives a task once it's under way. Another new session
    /// left empty has neither, and one left with a draft is the user's to find in the sidebar.
    private func hasWork(_ summary: SessionSummary) -> Bool {
        if let live = model.session(summary.id) { return !live.isTranscriptEmpty }
        guard !model.unsentSessions.contains(summary.id) else { return false }
        return summary.info.title?.isEmpty == false || model.userTitle(for: summary.id) != nil
    }

    /// The status every surface reads (`SessionModel.taskStatus`); a task not open in this run is idle.
    private func status(of session: SessionModel?) -> TaskStatus {
        session?.taskStatus ?? .idle
    }

    private var pullRequests: [NewSessionContext.PullRequest] {
        guard !repositories.isEmpty, let inbox = gitHub.inbox else { return [] }
        let reviewRequested = Set(inbox.reviewRequested.map(\.id))
        let canOpen = gitHub.canOpenAsTask
        return inbox.all
            .filter { $0.state == .open && repositories.contains($0.repository.lowercased()) }
            // Reviews asked of the user first: they're waiting on someone. Then the latest.
            .sorted {
                (reviewRequested.contains($0.id) ? 1 : 0, $0.updatedAt)
                    > (reviewRequested.contains($1.id) ? 1 : 0, $1.updatedAt)
            }
            .map { pullRequest in
                NewSessionContext.PullRequest(
                    id: pullRequest.id,
                    number: pullRequest.number,
                    title: pullRequest.title,
                    isReviewRequested: reviewRequested.contains(pullRequest.id),
                    branch: pullRequest.headRefName,
                    openAsTask: canOpen ? { [gitHub] in gitHub.requestOpenAsTask(pullRequest) } : nil
                )
            }
    }

    private var actions: [NewSessionContext.Action] {
        let target = ProjectActionTarget(project: project, session: session)
        let last = runner.store.lastRunAction(in: project)?.id
        return runner.store.list(for: project).all.map { action in
            let isRunning = runner.state(of: action, in: target)?.isRunning == true
            return NewSessionContext.Action(
                id: action.id.rawValue,
                name: action.name,
                command: action.command,
                isRunning: isRunning,
                isLast: action.id == last,
                run: { [runner] in
                    if isRunning { runner.stop(action, in: target) } else { runner.run(action, in: target) }
                }
            )
        }
    }
}
