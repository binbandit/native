import ACP
import Foundation
import Git
import GitHub
import ProjectActions
import TaskScripts

/// Builds a new session's `NewSessionContext` from what the app already holds: the project and its
/// tasks, git's status of the task's folder and the project's checkout, the GitHub inbox, the
/// project's actions and the worktree's setup. Nothing here runs git or gh; the views ask for this
/// on every update, so it only reads.
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
    /// The project's repositories on GitHub, lowercased `owner/name`, origin first, once read.
    let repositories: [String]

    func context() -> NewSessionContext {
        let checkout = git.model(for: project.url)
        let registry = CommandRegistry.shared
        return NewSessionContext(
            projectName: project.name,
            projectIcon: ProjectIconStore.shared.icon(for: project, size: NewSessionMetrics.titleIcon),
            workspace: workspace(checkout: checkout),
            checkoutChanges: checkout.status?.changedFileCount ?? 0,
            tasks: tasks,
            pullRequests: pullRequests,
            repository: repositories.first.flatMap { name in
                // As GitHub spells it, from a pull request, rather than lowercased.
                gitHub.inbox?.all.first { $0.repository.lowercased() == name }?.repository ?? name
            },
            actions: actions,
            setup: setup,
            keys: NewSessionContext.Keys(
                palette: registry.keyboardShortcut(for: .paletteShow)?.displayString,
                runLast: registry.keyboardShortcut(for: .projectActionsRunLast)?.displayString,
                terminal: registry.keyboardShortcut(for: .terminalToggle)?.displayString),
            draft: { [session] text in
                session.draft = text
                session.wantsComposerFocus = true
            },
            editActions: { [runner, settings, project] in
                if runner.store.list(for: project).all.isEmpty {
                    runner.store.requestNewAction(in: project)
                }
                settings.open(.project(project.id))
            }
        )
    }

    private func workspace(checkout: GitRepositoryModel) -> NewSessionContext.Workspace {
        let folder = git.model(for: session.cwd)
        switch folder.state {
        case .loading, .failed:
            return .unknown(path: session.cwd.abbreviatedPath)
        case .notRepository:
            return .folder(path: session.cwd.abbreviatedPath)
        case .ready:
            let branch = folder.branch?.name
            guard !SessionFolder.isSame(session.cwd.folderPath, project.path) else { return .checkout(branch: branch) }
            // The branch the worktree was made from, as its setup recorded it; else what the project's
            // checkout is on, which it was made from a moment ago.
            let base = scripts.setupRun(in: session.cwd)?.context.baseBranch ?? checkout.branch?.name
            return .worktree(branch: branch ?? folder.branch?.displayName ?? "", base: base)
        }
    }

    private var tasks: [NewSessionContext.RecentTask] {
        model.sessions(in: project.id)
            .filter { $0.id != session.key && model.session($0.id)?.isTranscriptEmpty != true }
            .map { summary in
                let live = model.session(summary.id)
                return NewSessionContext.RecentTask(
                    id: "\(summary.id.agent.rawValue)/\(summary.id.id.rawValue)",
                    title: model.title(for: summary),
                    agentName: summary.agent.displayName,
                    status: status(of: live),
                    date: live?.lastActivity ?? summary.info.updatedDate,
                    open: { [model] in model.selection = summary.id }
                )
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func status(of session: SessionModel?) -> TaskStatus {
        switch session?.wait {
        case .input: .needsInput
        case .permission: .needsPermission
        case .planReview: .needsPlanReview
        case nil: TaskStatus(session)
        }
    }

    private var pullRequests: [NewSessionContext.PullRequest] {
        guard !repositories.isEmpty, let inbox = gitHub.inbox else { return [] }
        let reviewRequested = Set(inbox.reviewRequested.map(\.id))
        let canOpen = gitHub.canOpenAsTask
        return inbox.all
            .filter { $0.state == .open && repositories.contains($0.repository.lowercased()) }
            .map { pullRequest in
                NewSessionContext.PullRequest(
                    id: pullRequest.id,
                    number: pullRequest.number,
                    title: pullRequest.title,
                    isDraft: pullRequest.isDraft,
                    isReviewRequested: reviewRequested.contains(pullRequest.id),
                    branch: pullRequest.headRefName,
                    updatedAt: pullRequest.updatedAt,
                    openAsTask: canOpen ? { [gitHub] in gitHub.requestOpenAsTask(pullRequest) } : nil
                )
            }
            // Reviews asked of the user first: they're waiting on someone.
            .sorted { ($0.isReviewRequested ? 1 : 0, $0.updatedAt) > ($1.isReviewRequested ? 1 : 0, $1.updatedAt) }
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
                icon: action.icon ?? ProjectActionGlyph.fallback,
                isRunning: isRunning,
                isLast: action.id == last,
                run: { [runner] in
                    if isRunning { runner.stop(action, in: target) } else { runner.run(action, in: target) }
                }
            )
        }
    }

    private var setup: NewSessionContext.Setup? {
        guard let run = scripts.setupRun(in: session.cwd) else { return nil }
        switch run.state {
        case .awaitingApproval: return .waiting
        case .running: return .running(since: run.startedAt)
        case .succeeded: return .done(seconds: run.duration)
        case .failed(let report): return .failed(report.result.outcome.phrase)
        case .skipped: return nil
        }
    }
}
