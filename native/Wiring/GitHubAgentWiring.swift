import Foundation
import Git
import GitHub

/// "Ask an Agent" on a pull request's lines: the GitHub feature writes the prompt (the lines as
/// diff, the review comments, the request); this starts a task on the pull request's branch with
/// it, or sends it to the task on screen.
enum GitHubAgentWiring {
    enum AskError: LocalizedError {
        case noCurrentTask

        var errorDescription: String? {
            switch self {
            case .noCurrentTask: "No task is open to send this to. Open a task, or ask in a new one."
            }
        }
    }

    static func ask(
        _ prompt: ReviewAgentPrompt, destination: GitHubAgentDestination, app: AppModel, git: GitStore,
        gitHub: GitHubModel
    ) async throws {
        switch destination {
        case .currentTask:
            guard let session = currentTask(app: app) else { throw AskError.noCurrentTask }
            try await session.submit(prompt.text, .queue)
        case .newTask:
            // The same checkout as "Open as Task": a fresh worktree on the pull request's branch.
            let pullRequest = PullRequestSummary(
                url: prompt.reference.url, repository: prompt.reference.repository, number: prompt.reference.number,
                title: prompt.title, createdAt: .now, updatedAt: .now, headRefName: prompt.branch)
            let session = try await GitHubGitWiring.openAsTask(pullRequest, app: app, git: git, gitHub: gitHub)
            try await session.submit(prompt.text, .queue)
            app.selection = session.key
        }
    }

    static func currentTask(app: AppModel) -> SessionModel? {
        app.selection.flatMap(app.session)
    }
}
