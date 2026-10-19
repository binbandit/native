import NativeCommands

extension CommandID {
    static let pullRequestOpenAsTask: Self = "pullRequest.openAsTask"
}

extension NativeCommand {
    /// File ▸ Open Pull Request as Task…: pick one of the user's pull requests, or paste a link.
    static func pullRequestTasks(_ opener: PullRequestTaskOpener) -> NativeCommand {
        NativeCommand(
            .pullRequestOpenAsTask, title: "Open Pull Request as Task…", category: .tasks,
            systemImage: "arrow.triangle.pull", keywords: ["github", "pr", "checkout", "worktree", "review", "fork"]
        ) { context in
            // The sheet shows over the main window, so bring it back if it was closed.
            context.openMainWindow()
            opener.pick()
        }
    }
}
