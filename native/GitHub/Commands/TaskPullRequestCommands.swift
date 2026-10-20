import GitHub
import NativeCommands

extension CommandID {
    static let pullRequestOpenForTask: Self = "pullRequest.openForTask"
}

extension NativeCommand {
    /// Session ▸ Open Pull Request (⌥⌘P): the visible task's pull request, where clicking one goes
    /// (Settings › GitHub). `pullRequest` finds it, since the app knows which branch a task is on.
    static func taskPullRequest(
        _ gitHub: GitHubModel, pullRequest: @escaping @MainActor (CommandContext) -> PullRequestSummary?
    ) -> NativeCommand {
        NativeCommand(
            .pullRequestOpenForTask, title: "Open Task's Pull Request", category: .tasks,
            systemImage: "arrow.triangle.pull", keywords: ["github", "pr", "branch"]
        ) { context in
            guard let found = pullRequest(context) else { return }
            gitHub.open(found)
        }
        .menuTitle { context in pullRequest(context).map { "Open Pull Request #\($0.number)" } ?? "Open Pull Request" }
        .available { pullRequest($0) != nil }
    }
}
