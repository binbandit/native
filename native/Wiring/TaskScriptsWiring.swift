import Foundation

/// Connects the task scripts to the rest of the app: git tells them about worktrees it makes and
/// removes, the app model holds a task's turns while its setup runs and says which task works in a
/// folder, and session events reach them through `TaskScriptsSessionPlugin`.
enum TaskScriptsWiring {
    static func connect(_ center: TaskScriptCenter, model: AppModel, git: GitStore) {
        TaskScriptsSessionPlugin.center = center
        center.environment = { await model.shellEnvironment() }
        center.holdTurns = { [weak model] folder, reason in
            model?.holdTurns(in: folder, because: reason)
        }
        center.lookUpTask = { [weak model] folder in
            // The task itself, not one of its subagents working in the same folder.
            model?.sessions.open(in: folder).first { $0.root === $0 }.map { TaskScriptTask($0.context) }
        }
        center.lookUpFolder = { [weak git] folder in
            guard let checkout = await git?.checkout(of: folder) else { return nil }
            return TaskScriptFolder(projectRoot: checkout.main, branch: checkout.branch)
        }
        center.makeScratchWorktree = { [weak git] project in
            guard let git else { throw CancellationError() }
            return try await git.makeScratchWorktree(of: project)
        }
        center.removeScratchWorktree = { [weak git] folder in
            await git?.removeScratchWorktree(at: folder)
        }
        git.beforeCreatingTaskWorktree = { [weak center] worktree in
            try await center?.beforeWorktree(
                folder: worktree.folder, projectRoot: worktree.projectRoot, branch: worktree.branch)
        }
        git.onTaskWorktreeCreated = { [weak center] worktree in
            center?.worktreeCreated(
                folder: worktree.folder, projectRoot: worktree.projectRoot, branch: worktree.branch,
                baseBranch: worktree.baseBranch, copiedFiles: worktree.copiedFiles, copyFailure: worktree.copyFailure,
                baseNotice: worktree.baseNotice)
        }
        git.beforeRemovingTaskWorktree = { [weak center] worktree in
            await center?.teardown(folder: worktree.folder, projectRoot: worktree.projectRoot, branch: worktree.branch)
        }
    }
}
