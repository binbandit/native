import NativeCommands

extension CommandID {
    static let gitCleanUpMerged: Self = "git.cleanUpMerged"
}

extension NativeCommand {
    /// File ▸ Clean Up Merged Branches…: the current project's merged task worktrees, branches and
    /// stale worktree records, to review before anything goes. Also in a project's context menu.
    static func gitCleanUpMerged(_ center: GitCleanupCenter, model: AppModel) -> NativeCommand {
        NativeCommand(
            .gitCleanUpMerged, title: "Clean Up Merged Branches…", category: .tasks,
            systemImage: "arrow.triangle.merge",
            keywords: ["git", "branches", "worktrees", "merged", "prune", "delete", "tidy", "clean up", "squash"]
        ) { context in
            guard let project = model.currentProject else { return }
            // The sheet shows over the main window, so bring it back if it was closed.
            context.openMainWindow()
            center.open(project)
        }
        .available { _ in model.currentProject != nil }
    }
}
