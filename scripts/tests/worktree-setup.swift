import Exec
import Foundation
import Git
import NativePolicy
import TaskScripts
import Terminal

@testable import Native

@main
@MainActor
private struct WorktreeSetupRegression {
    private static var failures = 0

    static func main() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "worktree-setup-model-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let project = scratch.appending(path: "project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let runner = LocalCommandRunner()
        var environment = ProcessInfo.processInfo.environment
        environment.merge([
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "SHELL": "/bin/sh",
            "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.com",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.com",
        ]) { $1 }
        for arguments in [
            ["init", "--quiet", "--initial-branch=main"], ["commit", "--quiet", "--allow-empty", "-m", "Initial"],
        ] {
            let result = try await runner.run(Command("git", arguments, in: project.path(), environment: environment))
            check(result.succeeded, "fixture git succeeds")
        }
        var policy = NativePolicy.default
        let settings = TaskScriptSettings(defaults: PreviewUserDefaults(), policy: { policy })
        let center = TaskScriptCenter(settings: settings, runner: runner)
        center.environment = { environment }
        let app = AppModel.preview(.empty)
        let git = GitStore(
            environment: { environment }, settings: GitSettings(defaults: PreviewUserDefaults()),
            worktreesFolder: scratch.appending(path: "worktrees"), makeGit: { Git(environment: $0) })
        git.allowsWorktreeFetch = { false }
        TaskScriptsWiring.connect(center, model: app, git: git)
        center.environment = { environment }
        var holds: [String] = []
        center.holdTurns = { _, reason in if let reason { holds.append(reason) } }
        let terminals = TerminalStore(
            preferences: TerminalPreferences(defaults: PreviewUserDefaults()), makeEngine: { .failure(.notBuilt) })
        TaskScriptsTerminalWiring.connect(center, model: app, terminals: terminals)
        func runGit(_ arguments: [String]) async throws -> String {
            let result = try await runner.run(Command("git", arguments, in: project.path(), environment: environment))
            guard result.succeeded else { throw Failure.missing("fixture git command") }
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let remote = scratch.appending(path: "origin.git")
        _ = try await runGit(["init", "--bare", "--quiet", remote.path()])
        _ = try await runGit(["remote", "add", "origin", remote.path()])
        _ = try await runGit(["push", "--quiet", "--set-upstream", "origin", "main"])
        let localHead = try await runGit(["rev-parse", "HEAD"])
        try Data("remote update".utf8).write(to: project.appending(path: "remote.txt"))
        _ = try await runGit(["add", "remote.txt"])
        _ = try await runGit(["commit", "--quiet", "-m", "Remote update"])
        _ = try await runGit(["push", "--quiet", "origin", "main"])
        _ = try await runGit(["reset", "--hard", localHead])
        git.allowsWorktreeFetch = { true }
        guard let fresh = try await git.prepareTaskCheckout(in: project, prefix: "fresh/") else {
            throw Failure.missing("fresh checkout")
        }
        check(
            FileManager.default.fileExists(atPath: fresh.folder.appending(path: "remote.txt").path()),
            "model creates worktree from the new remote commit")
        check(try await runGit(["rev-parse", "HEAD"]) == localHead, "model leaves the local branch unchanged")
        git.allowsWorktreeFetch = { false }
        settings.setProjectScript("printf before > before.txt", for: .beforeWorktree, at: project)
        settings.setProjectScript(
            #"test -f "$NATIVE_PROJECT_PATH/before.txt" || exit 9; printf '%s\n' "$PWD"; printf started > started.txt; worktree_wait=0; while [ ! -f release.txt ] && [ "$worktree_wait" -lt 200 ]; do sleep 0.05; worktree_wait=$((worktree_wait + 1)); done; exit 7"#,
            for: .afterWorktree, at: project)
        let checkout = try await git.prepareTaskCheckout(in: project, prefix: "fixture/")
        guard let checkout else { throw Failure.missing("checkout") }
        guard let run = center.runs(in: checkout.folder).first(where: { $0.event == .afterWorktree }) else {
            throw Failure.missing("after run")
        }
        defer { center.stop(run) }
        check(run.isRunning, "worktree creation returns while the after-command is running")
        check(holds.isEmpty, "after-commands never hold the task's first message")
        check(
            FileManager.default.fileExists(atPath: project.appending(path: "before.txt").path()),
            "before-command ran in the project")
        guard let session = SessionModel.preview(in: app, agent: "codex", cwd: checkout.folder.path()) else {
            throw Failure.missing("task")
        }
        center.taskStarted(in: checkout.folder, task: TaskScriptTask(id: session.id.rawValue, agent: "codex"))
        let panel = terminals.panel(for: session)
        guard let tab = panel.tabs.selected, let log = panel.logs[tab.id] else { throw Failure.missing("terminal log") }
        check(panel.isVisible && log.job.isRunning, "after-command appears in a terminal tab without a terminal engine")
        try await waitForFile(checkout.folder.appending(path: "started.txt"))
        try Data().write(to: checkout.folder.appending(path: "release.txt"))
        await run.work?.value
        check(run.isFailure, "nonzero exit is a task script failure")
        check(
            log.job.outcome == .exited(status: 7, duration: .seconds(run.duration ?? 0)),
            "terminal tab keeps the failure status")
        let printedFolder = log.output.split(separator: "\n").first { $0.hasPrefix("/") }.map(String.init)
        check(
            printedFolder.map { URL(filePath: $0).resolvingSymlinksInPath().standardizedFileURL.pathComponents }
                == checkout.folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents,
            "terminal output shows execution in the task worktree")
        settings.setProjectScript("printf retried > retried.txt; echo recovered", for: .afterWorktree, at: project)
        panel.rerunJob(in: tab.id)
        await run.work?.value
        check(
            run.state == .succeeded && log.output.contains("recovered"),
            "Retry reads the edited command and updates terminal output")
        check(
            FileManager.default.fileExists(atPath: checkout.folder.appending(path: "retried.txt").path()),
            "Retry uses the same worktree")
        policy.taskScripts.userScriptsEnabled = false
        settings.setProjectScript("touch forbidden.txt", for: .afterWorktree, at: project)
        panel.rerunJob(in: tab.id)
        await run.work?.value
        check(
            !FileManager.default.fileExists(atPath: checkout.folder.appending(path: "forbidden.txt").path()),
            "Retry obeys changed policy")
        check(run.state == .skipped && !run.isFailure, "disabled commands are skipped without a failure")
        policy.taskScripts.userScriptsEnabled = true
        settings.setProjectScript("sleep 10", for: .afterWorktree, at: project)
        panel.rerunJob(in: tab.id)
        try await Task.sleep(for: .milliseconds(200))
        panel.stopJob(in: tab.id)
        await run.work?.value
        check(run.state == .skipped && !run.isFailure, "Stop does not show a command failure")
        check(log.job.isStopping, "terminal keeps the intentionally stopped status")
        panel.close(tab.id)
        settings.setProjectScript("echo reopened; sleep 10", for: .afterWorktree, at: project)
        center.retry(run)
        try await Task.sleep(for: .milliseconds(200))
        check(panel.logs.count == 1, "Retry reopens a closed command tab once")
        for _ in 0...TaskScriptCenter.logLimit {
            center.record(
                TaskScriptRun(
                    event: .turnFinished, folder: checkout.folder, projectRoot: project,
                    context: TaskScriptContext(
                        event: .turnFinished, projectPath: project.path(), worktreePath: checkout.folder.path()),
                    plan: TaskScriptPlan(event: .turnFinished, scripts: [], timeout: .seconds(10)), state: .succeeded))
        }
        check(center.runs(in: checkout.folder).contains { $0 === run }, "history retains an active after-command")
        await center.teardown(folder: checkout.folder, projectRoot: project, branch: checkout.branch)
        check(run.state == .skipped, "teardown waits for the after-command to stop before removing its folder")
        settings.setProjectScript("exit 12", for: .beforeWorktree, at: project)
        let repository = try await git.requireRepository(at: project)
        let before = try await repository.worktrees().count
        do {
            _ = try await git.prepareTaskCheckout(in: project, prefix: "failure/")
            check(false, "before-command failure prevents creation")
        } catch {
            check(error.localizedDescription.contains("12"), "before-command failure explains the exit status")
        }
        check(try await repository.worktrees().count == before, "failed before-command leaves no worktree")
        settings.setProjectScript("touch cancelling.txt; sleep 10", for: .beforeWorktree, at: project)
        let cancelled = Task { try await git.prepareTaskCheckout(in: project, prefix: "cancelled/") }
        try await waitForFile(project.appending(path: "cancelling.txt"))
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            check(false, "cancelling creation stops the before-command")
        } catch is CancellationError {
        } catch {
            check(false, "creation cancellation stays a cancellation")
        }
        check(try await repository.worktrees().count == before, "cancelled before-command leaves no worktree")
        settings.setProjectScript("exit 13", for: .beforeWorktree, at: project)
        settings.setProjectScript("", for: .afterWorktree, at: project)
        let archived = ArchivedWorktree(path: fresh.folder, branch: fresh.branch, checkpoint: nil)
        try await repository.recordArchivedWorktree(archived)
        try await repository.removeWorktree(at: fresh.folder, force: true)
        do {
            _ = try await git.restoreArchivedTaskWorktree(archived, of: project)
            check(false, "a failed before-command prevents restoration")
        } catch {
            check(error.localizedDescription.contains("13"), "restoration explains a failed before-command")
        }
        check(
            try await repository.archivedWorktrees().contains { $0.branch == archived.branch },
            "a failed before-command preserves the archived worktree record")
        settings.setProjectScript("printf restored > restored-before.txt", for: .beforeWorktree, at: project)
        settings.setProjectScript("echo restored output", for: .afterWorktree, at: project)
        let restored = try await git.restoreArchivedTaskWorktree(archived, of: project)
        guard let restoredRun = center.runs(in: restored).last(where: { $0.event == .afterWorktree }) else {
            throw Failure.missing("restored after-command")
        }
        await restoredRun.work?.value
        settings.setProjectScript("touch should-not-start.txt", for: .taskStarted, at: project)
        guard let reopened = SessionModel.preview(in: app, agent: "codex", cwd: restored.path()) else {
            throw Failure.missing("restored task")
        }
        let restoredPanel = terminals.panel(for: reopened)
        check(
            restoredPanel.logs.values.contains { $0.output.contains("restored output") && !$0.job.isRunning },
            "opening an existing task backfills its completed after-command")
        check(
            !center.runs(in: restored).contains { $0.event == .taskStarted },
            "backfilling does not rerun task-started scripts")
        if let restoredTab = restoredPanel.tabs.selected {
            restoredPanel.close(restoredTab.id)
            app.sessions.register(reopened)
            check(restoredPanel.logs.isEmpty, "registering a task again preserves a deliberately closed log tab")
        }
        restoredPanel.closeAll()
        check(
            FileManager.default.fileExists(atPath: project.appending(path: "restored-before.txt").path()),
            "restoring an archived worktree runs its before-command")
        check(
            FileManager.default.fileExists(atPath: restored.appending(path: "remote.txt").path()),
            "restoration preserves the archived branch rather than choosing a new base")
        check(
            !center.failures(in: restored).contains { $0.event == .beforeWorktree },
            "a successful creation retry does not leave an obsolete before-command failure banner")
        panel.closeAll()
        if failures > 0 { exit(1) }
        print("PASS: before/after worktree commands, nonblocking creation, terminal output, Retry and managed policy")
    }

    private static func waitForFile(_ url: URL) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: url.path()) {
            guard ContinuousClock.now < deadline else { throw Failure.missing(url.lastPathComponent) }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func check(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \(message)"); failures += 1 }
    }

    private enum Failure: Error { case missing(String) }
}
