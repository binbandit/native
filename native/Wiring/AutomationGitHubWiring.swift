import Foundation
import Git
import GitHub

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
        let base = (try? await gitHub.repository(of: repository.root))?.defaultBranch
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
