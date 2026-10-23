import Exec
import Foundation
import ProjectActions

@testable import Native

private struct InertActionRunner: CommandRunner {
    func run(_ command: Command) async throws -> CommandResult {
        if command.arguments.last == "wait" {
            try await Task.sleep(for: .seconds(60))
        }
        return CommandResult(exitCode: 1, standardOutput: Data(), standardError: Data())
    }
}

@main
@MainActor
private struct ProjectActionsRunChecks {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "polish-run-\(UUID())")
        try FileManager.default.createDirectory(
            at: folder.appending(path: ".native"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = PreviewUserDefaults()
        let store = ProjectActionStore(defaults: defaults)
        let runner = ProjectActionRunner(
            store: store, terminals: TerminalStore(preferences: TerminalPreferences(defaults: defaults)))
        runner.hooks.environment = { ["SHELL": "/bin/sh"] }
        runner.hooks.commandRunner = InertActionRunner()
        let project = Project(url: folder)
        let target = ProjectActionTarget(project: project, session: nil)
        require(runner.headerAction(in: target) == nil, "Empty project has no primary action")

        let test = ProjectAction(name: "Test", command: "wait", presentation: .background)
        let lint = ProjectAction(name: "Lint", command: "wait", presentation: .background)
        store.add(test, to: project)
        store.add(lint, to: project)
        require(runner.headerAction(in: target)?.id == test.id, "First own action is the initial fallback")
        runner.runLast(in: target)
        require(runner.state(of: test, in: target)?.isRunning == true, "Run Last uses the initial fallback")
        runner.run(lint, in: target)
        require(runner.headerAction(in: target)?.id == lint.id, "Newest running action names the primary half")
        require(runner.running(in: target).count == 2, "Both actions remain running")
        // The project-level last-run preference must not override this task's active run.
        store.recordRun(test.id, in: project)
        require(
            runner.headerAction(in: target)?.id == lint.id, "Newest run wins over the project's last-run preference")
        runner.stop(lint, in: target)
        require(runner.state(of: lint, in: target)?.isStopping == true, "Stop exposes the stopping state")
        try await until { runner.state(of: lint, in: target)?.isRunning == false }
        require(runner.headerAction(in: target)?.id == test.id, "The remaining run becomes primary")
        runner.stop(test, in: target)
        try await until { runner.state(of: test, in: target)?.isRunning == false }
        require(runner.headerAction(in: target)?.id == test.id, "Idle control returns to the last action")

        let failure = ProjectAction(name: "Failure", command: "fail", presentation: .background)
        store.add(failure, to: project)
        runner.run(failure, in: target)
        try await until { runner.state(of: failure, in: target)?.hasFailed == true }
        require(runner.headerAction(in: target)?.id == failure.id, "Failure stays named for retry")
        store.remove(failure.id, from: project)
        store.remove(test.id, from: project)
        store.remove(lint.id, from: project)

        try Data(#"{"actions":[{"name":"Repo Test","command":"fail","runIn":"background"}]}"#.utf8)
            .write(to: folder.appending(path: ProjectActionFile.path))
        store.refresh(project)
        try await until { store.list(for: project).hasScanned }
        require(runner.headerAction(in: target)?.name == "Repo Test", "Repo action is the final fallback")
        runner.runLast(in: target)
        require(runner.pendingRun?.action.name == "Repo Test", "Repo fallback still requires approval")
        require(runner.running(in: target).isEmpty, "Unapproved repo action never starts")
        store.allowsRepositoryActions = { false }
        require(runner.headerAction(in: target) == nil, "Policy removes repo actions from the primary choice")
        require(store.hasRepositoryFile(in: project), "Policy explanation can still identify an existing repo file")
        store.add(test, to: project)
        require(runner.headerAction(in: target)?.id == test.id, "Own actions remain available under policy")
        print("PASS: first action, newest run, stopping, failure, repo approval and policy fallback")
    }

    static func require(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func until(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        require(predicate(), "Timed out waiting for the runner")
    }
}
