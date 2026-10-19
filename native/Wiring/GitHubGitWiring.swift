import Foundation
import Git
import GitHub

/// Connects the Git and GitHub features, which don't know about each other: creating a pull
/// request from the commit UI, opening a pull request as a task in its own worktree, and finding
/// the pull request a task's branch was checked out for.
enum GitHubGitWiring {
    enum TaskError: LocalizedError {
        case noProject(repository: String)

        var errorDescription: String? {
            switch self {
            case .noProject(let repository):
                "None of your projects is a checkout of \(repository). Open the pull request as a task to clone it, then try again."
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

    /// Opens a pull request as a task without asking, for "Ask an Agent" in a new task: the task
    /// already working on it, or a new checkout in the project that has its repository. Without
    /// such a project it throws; Open as Task is where cloning one is offered.
    @discardableResult
    static func openAsTask(
        _ pullRequest: PullRequestSummary, app: AppModel, git: GitStore, gitHub: GitHubModel
    ) async throws -> SessionModel {
        guard let reference = PullRequestReference(pullRequest) else {
            throw TaskError.noProject(repository: pullRequest.repository)
        }
        let checkout = PullRequestTaskCheckout(app: app, git: git, gitHub: gitHub)
        switch try await checkout.resolve(reference) {
        case .existing(let task):
            await checkout.show(task)
            guard let session = await app.loadedSession(task.key) else {
                throw SessionLauncher.LaunchError.agentUnavailable(task.key.agent.rawValue)
            }
            return session
        case .checkout(let project):
            return try await checkout.open(project, includeReviews: false) { _ in }
        case .noProject:
            throw TaskError.noProject(repository: pullRequest.repository)
        }
    }

    /// The pull request a task's branch was checked out for, from the note Open as Task keeps with
    /// it, so the task's badge finds it although the branch has a name of its own.
    static func linkedPullRequest(for branch: BranchReference, git: GitStore) async -> URL? {
        guard let repository = try? await git.requireRepository(at: branch.directory),
            let link = try? await repository.notes(PullRequestTaskCheckout.linkNote)[branch.branch]
        else { return nil }
        return URL(string: link)
    }

    // MARK: - Helpers

    private static func template(in repository: Repository) async -> String? {
        for path in templatePaths {
            if let data = try? await repository.contents(of: path, at: .head) {
                return String(decoding: data, as: UTF8.self)
            }
        }
        return nil
    }
}
