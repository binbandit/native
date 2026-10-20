#if NATIVE_PREVIEWS_WIP
import Exec
import Foundation
import TaskScripts

/// Task scripts for previews: runs built as values in each state, and a center whose settings live
/// in memory and whose command runner runs nothing.
enum TaskScriptsPreviewFixtures {
    static let project = URL(filePath: "/Users/preview/Developer/native", directoryHint: .isDirectory)
    static let worktree = URL(
        filePath: "/Users/preview/.native/worktrees/native/queue-follow-ups", directoryHint: .isDirectory)

    static let setupScript = TaskScript(
        event: .setup, source: .project, text: "#!/bin/sh\nset -e\nbun install\ncp ../native/.env.local .env.local\n")

    static func settings() -> TaskScriptSettings {
        TaskScriptSettings(defaults: PreviewUserDefaults())
    }

    static func center() -> TaskScriptCenter {
        TaskScriptCenter(settings: settings(), runner: TaskScriptsPreviewRunner())
    }

    static func run(
        _ event: TaskScriptEvent = .setup, state: TaskScriptRun.State, output: [String] = [],
        script: TaskScript = setupScript
    ) -> TaskScriptRun {
        let run = TaskScriptRun(
            event: event, folder: worktree, projectRoot: project,
            context: TaskScriptContext(
                event: event, projectPath: project.path, worktreePath: worktree.path, branch: "native/queue-follow-ups",
                baseBranch: "main", taskTitle: "Queue follow-ups while a turn runs", agent: "claude-code"),
            plan: TaskScriptPlan(
                event: event, scripts: state == .awaitingApproval ? [] : [script],
                awaitingApproval: state == .awaitingApproval
                    ? TaskScript(event: event, source: .repository, text: "#!/bin/sh\nmake bootstrap\n") : nil,
                timeout: .seconds(600)),
            state: state)
        run.current = state == .running ? script : nil
        run.startedAt = .now.addingTimeInterval(-38)
        if state != .running, state != .awaitingApproval {
            run.finishedAt = .now.addingTimeInterval(-2)
        }
        run.copiedFiles = event == .setup ? [".env.local"] : []
        for line in output {
            run.output.appendLine(line)
        }
        return run
    }

    static let installOutput = [
        "bun install v1.3.2", "Resolving dependencies", "Resolved, downloaded and extracted [412]",
        "Saved lockfile", "+ 412 packages installed [8.21s]",
    ]

    static let running = run(state: .running, output: installOutput)
    static let succeeded = run(state: .succeeded, output: installOutput)
    static let awaitingApproval = run(state: .awaitingApproval)
    static let failed = run(
        state: .failed(
            TaskScriptReport(
                script: setupScript, result: TaskScriptResult(outcome: .failed(exitCode: 1), duration: .seconds(9)))),
        output: Array(installOutput.prefix(2)) + [
            "error: lockfile had changes, but lockfile is frozen", "exit status 1",
        ])
    static let turnFailed = run(
        .turnFinished,
        state: .failed(
            TaskScriptReport(
                script: TaskScript(
                    event: .turnFinished, source: .global, text: "#!/bin/sh\nswift format lint --strict -r native\n"),
                result: TaskScriptResult(outcome: .timedOut(after: .seconds(120)), duration: .seconds(120)))),
        output: ["native/Views/Composer/ComposerView.swift:212:121: error: [LineLength] line is too long"])
}

/// Runs nothing, as if the shell weren't there, so no preview can start a script.
struct TaskScriptsPreviewRunner: CommandRunner {
    func run(_ command: Command) async throws -> CommandResult {
        throw CommandError.notFound(command.executable)
    }
}
#endif
