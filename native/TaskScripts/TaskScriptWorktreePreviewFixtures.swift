#if DEBUG
import Exec
import Foundation
import NativePolicy
import TaskScripts

/// In-memory examples for the worktree commands and their local-base notice.
enum TaskScriptWorktreePreviewFixtures {
    static let project = URL(filePath: "/work/project")
    static let folder = URL(filePath: "/work/task")

    static func center() -> TaskScriptCenter {
        TaskScriptCenter(settings: settings(), runner: Runner())
    }

    private struct Runner: CommandRunner {
        func run(_ command: Command) async throws -> CommandResult { throw CancellationError() }
    }

    static func settings() -> TaskScriptSettings {
        let settings = TaskScriptSettings(defaults: PreviewUserDefaults(), policy: { .default })
        settings.setProjectScript("git pull --ff-only", for: .beforeWorktree, at: project)
        settings.setProjectScript("pnpm install", for: .afterWorktree, at: project)
        return settings
    }

    static var localBase: TaskScriptRun {
        let run = TaskScriptRun(
            event: .setup, folder: folder, projectRoot: project,
            context: TaskScriptContext(event: .setup, projectPath: project.path(), worktreePath: folder.path()),
            plan: TaskScriptPlan(event: .setup, scripts: [], timeout: .seconds(600)), state: .succeeded)
        run.baseNotice = "Couldn't fetch the latest remote changes. This task starts from the local branch."
        return run
    }

    static var failedAfterCommand: TaskScriptRun {
        let script = TaskScript(event: .afterWorktree, source: .project, text: "pnpm install")
        let run = TaskScriptRun(
            event: .afterWorktree, folder: folder, projectRoot: project,
            context: TaskScriptContext(event: .afterWorktree, projectPath: project.path(), worktreePath: folder.path()),
            plan: TaskScriptPlan(event: .afterWorktree, scripts: [script], timeout: .seconds(600)),
            state: .failed(
                TaskScriptReport(script: script, result: .init(outcome: .failed(exitCode: 1), duration: .seconds(3)))))
        run.output.appendLine("Could not reach the package registry.")
        return run
    }
}
#endif
