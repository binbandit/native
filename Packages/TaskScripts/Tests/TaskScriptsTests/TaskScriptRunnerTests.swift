#if os(macOS)
import Exec
import Foundation
import Synchronization
import TaskScripts
import Testing

struct TaskScriptRunnerTests {
    private let runner = TaskScriptRunner(
        runner: LocalCommandRunner(), environment: ["PATH": "/usr/bin:/bin", "SHELL": "/bin/zsh"])

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory
        )
        .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func context(_ event: TaskScriptEvent = .setup, in folder: URL) -> TaskScriptContext {
        TaskScriptContext(
            event: event, projectPath: "/work/app", worktreePath: folder.path(percentEncoded: false), branch: "me/a1b2",
            taskTitle: "Fix login")
    }

    private func plan(_ texts: String..., timeout: Duration = .seconds(10)) -> TaskScriptPlan {
        TaskScriptPlan(
            event: .setup, scripts: texts.map { TaskScript(event: .setup, source: .project, text: $0) },
            timeout: timeout)
    }

    @Test func runsInTheWorktreeWithTheTasksVariables() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = Mutex(TaskScriptOutput())
        let reports = await runner.run(
            plan(#"pwd; echo "$NATIVE_EVENT $NATIVE_BRANCH $NATIVE_TASK_TITLE"; touch marker"#),
            context: context(in: folder)
        ) { chunk in output.withLock { $0.append(chunk) } }
        #expect(reports.map(\.result.outcome) == [.succeeded])
        // `pwd` spells the temporary folder from /private.
        #expect(output.withLock(\.text).hasSuffix("/\(folder.lastPathComponent)\nsetup me/a1b2 Fix login\n"))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "marker").path(percentEncoded: false)))
    }

    @Test func aFailureStopsTheScriptsAfterIt() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let started = Mutex<[String]>([])
        let reports = await runner.run(
            plan("echo first", "echo broken >&2; exit 3", "echo never"), context: context(in: folder),
            onStart: { script in started.withLock { $0.append(script.text) } }, onOutput: { _ in })
        #expect(reports.map(\.result.outcome) == [.succeeded, .failed(exitCode: 3)])
        #expect(started.withLock { $0 }.count == 2)
    }

    /// A committed script names its interpreter, so it runs the same for someone whose shell is fish.
    @Test func honorsTheInterpreterLine() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fish = TaskScriptRunner(
            runner: LocalCommandRunner(), environment: ["PATH": "/usr/bin:/bin", "SHELL": "/no/such/fish"])
        let output = Mutex(TaskScriptOutput())
        let reports = await fish.run(
            plan("#!/bin/bash -e\nwords=(one two)\necho \"${words[1]} $NATIVE_EVENT\"\nexit 4"),
            context: context(in: folder)
        ) { chunk in output.withLock { $0.append(chunk) } }
        #expect(reports.map(\.result.outcome) == [.failed(exitCode: 4)])
        #expect(output.withLock(\.text) == "two setup\n")
    }

    @Test func stopsAScriptThatRunsTooLongWithWhatItStarted() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ContinuousClock()
        let start = clock.now
        let reports = await runner.run(
            plan("echo waiting; sleep 30", timeout: .milliseconds(400)), context: context(in: folder)
        ) { _ in }
        #expect(reports.map(\.result.outcome) == [.timedOut(after: .milliseconds(400))])
        #expect(clock.now - start < .seconds(3))
    }

    @Test func cancellingStopsTheScript() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = runner
        let context = context(in: folder)
        let plan = plan("sleep 30", "echo never")
        let task = Task { await runner.run(plan, context: context) { _ in } }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        #expect(await task.value.map(\.result.outcome) == [.cancelled])
    }

    @Test func aScriptThatLeavesAServerRunningIsDoneWhenItExits() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ContinuousClock()
        let start = clock.now
        let reports = await runner.run(plan("sleep 3 & echo started"), context: context(in: folder)) { _ in }
        #expect(reports.map(\.result.outcome) == [.succeeded])
        #expect(clock.now - start < .seconds(2))
    }

    @Test func aMissingFolderCantStart() async {
        let missing = URL(filePath: "/no/such/worktree", directoryHint: .isDirectory)
        let reports = await runner.run(plan("true"), context: context(in: missing)) { _ in }
        guard case .couldNotStart = reports.first?.result.outcome else {
            Issue.record("Expected the script not to start, got \(reports)")
            return
        }
    }

    @Test func readsTheRepositorysScripts() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scripts = folder.appending(path: ".native", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "#!/bin/sh\nmake\n".write(to: scripts.appending(path: "setup.sh"), atomically: true, encoding: .utf8)
        try "\n".write(to: scripts.appending(path: "teardown.sh"), atomically: true, encoding: .utf8)
        try "ignored".write(to: scripts.appending(path: "pre-push.sh"), atomically: true, encoding: .utf8)
        #expect(TaskScriptRepositoryFiles.read(at: folder) == [.setup: "#!/bin/sh\nmake\n"])
    }
}
#endif
