import Foundation
import Git
import GitHub

/// Connects the Git and GitHub features, which don't know about each other: creating a pull
/// request from the commit UI, and opening a pull request as a task in its own worktree.
enum GitHubGitWiring {
    enum TaskError: LocalizedError {
        case noProject(repository: String)
        case noAgent

        var errorDescription: String? {
            switch self {
            case .noProject(let repository):
                "None of your projects is a checkout of \(repository). Add it as a project, then try again."
            case .noAgent:
                "No agent is ready to start a task. Check the agents at the bottom of the sidebar."
            }
        }
    }

    /// Where GitHub looks for a pull request template, in its order.
    private static let templatePaths = [
        ".github/pull_request_template.md", ".github/PULL_REQUEST_TEMPLATE.md",
        "docs/pull_request_template.md", "pull_request_template.md", "PULL_REQUEST_TEMPLATE.md",
    ]

    /// The commit UI's "Create PR": pushes the branch if the remote doesn't have it yet (gh never
    /// pushes), then opens the GitHub feature's sheet with the branch's commits and diff to draft from.
    static func createPullRequest(from model: GitRepositoryModel, gitHub: GitHubModel) async {
        guard let repository = model.repository, let head = model.branch?.name else { return }
        if model.canPush {
            await model.push()
            // The changes inspector already says why the push failed and what to do.
            if model.notice?.tone == .failure { return }
        }
        let base = (try? await gitHub.repository(of: repository.root))?.defaultBranch ?? "main"
        let comparison = (try? await repository.comparisonBase(for: base)) ?? base
        let commits = (try? await repository.commitLog(since: comparison)) ?? ""
        let diff = try? await repository.branchDiff(since: comparison)
        gitHub.invalidate(BranchReference(directory: repository.root, branch: head))
        gitHub.presentCreatePullRequest(
            CreatePullRequestRequest(
                directory: repository.root, head: head, base: base, commits: commits, diff: diff,
                template: await template(in: repository)
            ))
    }

    /// Checks a pull request out in a fresh worktree of the project it belongs to and starts a task
    /// there with the default agent, returning it.
    @discardableResult
    static func openAsTask(
        _ pullRequest: PullRequestSummary, app: AppModel, git: GitStore, gitHub: GitHubModel
    )
        async throws -> SessionModel
    {
        guard let project = await project(for: pullRequest.repository, app: app, gitHub: gitHub) else {
            throw TaskError.noProject(repository: pullRequest.repository)
        }
        guard let agent = app.defaultAgent?.id else { throw TaskError.noAgent }
        let worktree = try await git.createTaskWorktree(
            in: project.url, title: "pr \(pullRequest.number) \(pullRequest.title)", detached: true)
        let localBranch = await localBranchName(for: pullRequest, in: project.url, git: git)
        try await gitHub.cli().checkout(.number(pullRequest.number), in: worktree, localBranch: localBranch)
        return try await app.startTaskSession(agent: agent, cwd: worktree)
    }

    // MARK: - Helpers

    private static func project(for repository: String, app: AppModel, gitHub: GitHubModel) async -> Project? {
        for project in app.projects.all {
            if let match = try? await gitHub.repository(of: project.url),
                match.nameWithOwner.caseInsensitiveCompare(repository) == .orderedSame
            {
                return project
            }
        }
        return nil
    }

    /// The pull request's own branch name, so pushes go back to it, unless a local branch already
    /// has that name (often checked out in the main checkout, where git won't share it).
    private static func localBranchName(
        for pullRequest: PullRequestSummary, in folder: URL, git: GitStore
    ) async
        -> String
    {
        let fallback = "pr-\(pullRequest.number)"
        let model = git.model(for: folder)
        if model.repository == nil { await model.refreshNow() }
        guard let head = pullRequest.headRefName,
            let repository = model.repository,
            let branches = try? await repository.branches(includingRemote: false)
        else { return fallback }
        return branches.contains { $0.name == head } ? fallback : head
    }

    private static func template(in repository: Repository) async -> String? {
        for path in templatePaths {
            if let data = try? await repository.contents(of: path, at: .head) {
                return String(decoding: data, as: UTF8.self)
            }
        }
        return nil
    }
}
