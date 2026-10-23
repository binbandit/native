import Foundation
import TaskScripts

extension TaskScriptCenter {
    /// Before-commands run in the project checkout while the starting task waits. No worktree or
    /// branch exists yet if they fail, so the task's existing Retry safely tries the whole step again.
    func beforeWorktree(folder: URL, projectRoot: URL, branch: String?) async throws {
        let plan = settings.plan(for: .beforeWorktree, project: projectRoot)
        guard !plan.isEmpty else { return }
        if plan.awaitingApproval != nil {
            throw WorktreeScriptFailure(
                message: "Allow this project's repository scripts in Project Settings before creating its worktree.")
        }
        let run = TaskScriptRun(
            event: .beforeWorktree, folder: folder, projectRoot: projectRoot,
            context: TaskScriptContext(
                event: .beforeWorktree, projectPath: projectRoot.folderPath,
                worktreePath: projectRoot.folderPath, branch: branch), plan: plan, state: .running)
        record(run)
        start(run)
        if let work = run.work {
            await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
        }
        try Task.checkCancellation()
        if let failure = run.failure {
            throw WorktreeScriptFailure(
                message:
                    "Before creating a worktree \(failure.result.outcome.phrase). Fix the command in Project Settings, then retry.\n\(run.output.lastLines(8).joined(separator: "\n"))"
            )
        }
    }

    func startAfterWorktree(folder: URL, projectRoot: URL, branch: String?, baseBranch: String?) {
        let plan = settings.plan(for: .afterWorktree, project: projectRoot)
        guard !plan.isEmpty else { return }
        let run = TaskScriptRun(
            event: .afterWorktree, folder: folder, projectRoot: projectRoot,
            context: TaskScriptContext(
                event: .afterWorktree, projectPath: projectRoot.folderPath,
                worktreePath: folder.folderPath, branch: branch, baseBranch: baseBranch),
            plan: plan, state: .running)
        if plan.awaitingApproval != nil {
            run.output.appendLine(
                "Skipped the repository's after-command. Allow repository scripts in Project Settings to run it.")
        }
        record(run)
        if plan.scripts.isEmpty { finish(run, as: .skipped) } else { start(run) }
    }
}

private struct WorktreeScriptFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
