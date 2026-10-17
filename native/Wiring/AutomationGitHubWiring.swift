import Foundation
import Git
import GitHub
import NativeAutomation

/// Connects workflows' "open pull request" step to the Git and GitHub features. The step's gate is
/// where the user reviews the title and body, so this opens the pull request directly instead of
/// presenting a second sheet: it pushes the branch if the remote doesn't have it (gh never pushes),
/// then creates the pull request and hands back its URL for the run.
enum AutomationGitHubWiring {
    enum PullRequestError: LocalizedError {
        case notARepository
        case onDefaultBranch(String)
        case pushFailed(String)

        var errorDescription: String? {
            switch self {
            case .notARepository:
                "The project isn't a git checkout on a branch, so there's nothing to open a pull request from."
            case .onDefaultBranch(let branch):
                "The changes are on \(branch), the default branch. A pull request needs them on a branch of their own."
            case .pushFailed(let reason):
                "Couldn't push the branch: \(reason)"
            }
        }
    }

    static func openPullRequest(_ draft: WorkflowPullRequestDraft, git: GitStore, gitHub: GitHubModel) async throws -> WorkflowPullRequestResult {
        let model = git.model(for: draft.cwd)
        if model.repository == nil {
            await model.refreshNow()
        }
        guard let repository = model.repository, let head = model.branch?.name else { throw PullRequestError.notARepository }
        // Asked before pushing, so a checkout that isn't on GitHub is refused without a push to its
        // remote; the error carries GitHub's own reason and fix.
        let base = try await gitHub.repository(of: repository.root).defaultBranch
        if head == base {
            throw PullRequestError.onDefaultBranch(head)
        }
        if model.canPush {
            await model.push()
            if let notice = model.notice, notice.tone == .failure {
                throw PullRequestError.pushFailed(notice.message ?? notice.title)
            }
        }
        let pullRequest = NewPullRequest(title: draft.title, body: draft.body, head: head, base: base, isDraft: draft.isDraft)
        let url = try await gitHub.createPullRequest(pullRequest, in: repository.root)
        return WorkflowPullRequestResult(url: url, number: Int(url.lastPathComponent))
    }
}

extension AutomationGitHubWiring {
    /// The project's GitHub repository, for matching pull request events to automations.
    static func repository(of project: URL, gitHub: GitHubModel) async -> String? {
        try? await gitHub.repository(of: project).nameWithOwner
    }

    /// A fresh worktree for an automation's run, on a new branch named after it.
    static func worktree(for project: URL, title: String, git: GitStore) async throws -> URL {
        try await git.createTaskWorktree(in: project, title: title)
    }

    /// Why pull request events can't be seen.
    struct EventSourceError: LocalizedError {
        let errorDescription: String?
    }

    /// The user's open pull requests as the GitHub feature last saw them (it keeps the inbox fresh),
    /// for automations to compare between polls. Throws with the reason and the fix when GitHub
    /// can't be read.
    static func pullRequestSnapshots(gitHub: GitHubModel) async throws -> [PullRequestSnapshot] {
        if gitHub.inbox == nil {
            await gitHub.refresh()
        }
        switch gitHub.availability {
        case .notInstalled:
            throw EventSourceError(errorDescription: "The GitHub CLI (gh) isn't installed, so Native can't see pull request events. Install it (brew install gh), then run gh auth login.")
        case .notAuthenticated:
            throw EventSourceError(errorDescription: "gh isn't signed in, so Native can't see pull request events. Run gh auth login in a terminal; Native picks it up on its next check.")
        case .offline:
            throw EventSourceError(errorDescription: "You're offline, so Native can't see pull request events. They're picked up again when the network returns.")
        case .ready, nil:
            break
        }
        guard let inbox = gitHub.inbox else {
            throw EventSourceError(errorDescription: gitHub.lastError?.localizedDescription ?? "GitHub hasn't answered yet; Native tries again in two minutes.")
        }
        let authored = Set(inbox.authored.map(\.url))
        let reviewRequested = Set(inbox.reviewRequested.map(\.url))
        return inbox.all.map { pullRequest in
            PullRequestSnapshot(
                url: pullRequest.url, repository: pullRequest.repository, number: pullRequest.number, title: pullRequest.title,
                updatedAt: pullRequest.updatedAt, isAuthored: authored.contains(pullRequest.url),
                isReviewRequested: reviewRequested.contains(pullRequest.url), hasFailingChecks: pullRequest.checks?.state == .failing
            )
        }
    }
}
