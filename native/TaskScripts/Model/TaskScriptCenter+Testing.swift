import Foundation
import TaskScripts

extension TaskScriptCenter {
    func runTest(_ run: TaskScriptRun, in target: TestTarget) async {
        var scratch: URL?
        switch target {
        case .scratchWorktree(let project):
            guard let makeScratchWorktree else { return fail(run, "Scratch worktrees aren't available here.") }
            run.output.appendLine("Making a scratch worktree of \(project.lastPathComponent)…")
            do {
                let worktree = try await makeScratchWorktree(project)
                scratch = worktree.folder
                run.folder = worktree.folder
                run.projectRoot = project
                run.context.projectPath = project.folderPath
                run.context.worktreePath = worktree.folder.folderPath
                run.context.baseBranch = worktree.baseBranch
            } catch {
                return fail(run, "Couldn't make a scratch worktree: \(error.localizedDescription)")
            }
        case .task(let folder):
            if let info = await lookUpFolder(folder) {
                run.projectRoot = info.projectRoot
                run.context = context(
                    run.event, folder: folder, projectRoot: info.projectRoot, branch: info.branch,
                    task: lookUpTask(folder))
            }
        }
        await execute(run)
        if let scratch, let removeScratchWorktree {
            // In a task of its own, so stopping the test doesn't also stop the clean-up.
            await Task { await removeScratchWorktree(scratch) }.value
            run.output.appendLine("Removed the scratch worktree.")
        }
    }

}
