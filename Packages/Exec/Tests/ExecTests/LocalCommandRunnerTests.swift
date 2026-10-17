#if os(macOS)
import Exec
import Foundation
import Testing

struct LocalCommandRunnerTests {
    private let runner = LocalCommandRunner()
    private let environment = ["PATH": "/usr/bin:/bin"]

    @Test func capturesOutputErrorAndExitCode() async throws {
        let result = try await runner.run(Command("sh", ["-c", "printf out; printf err >&2; exit 3"], environment: environment))
        #expect(result.exitCode == 3)
        #expect(result.output == "out")
        #expect(result.errorOutput == "err")
    }

    @Test func passesInputDirectoryAndEnvironment() async throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path(percentEncoded: false)
        let result = try await runner.run(Command(
            "sh",
            ["-c", "cat; printf \" $GREETING \"; pwd"],
            in: directory,
            environment: environment.merging(["GREETING": "hi"]) { $1 },
            standardInput: Data("input".utf8)
        ))
        #expect(result.output.hasPrefix("input hi "))
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(directory.trimmingCharacters(in: ["/"])))
    }

    /// More output than a pipe buffer holds must not deadlock.
    @Test func drainsLargeOutput() async throws {
        let result = try await runner.run(Command("sh", ["-c", "head -c 1000000 /dev/zero"], environment: environment))
        #expect(result.standardOutput.count == 1_000_000)
    }

    @Test func missingExecutableIsNotFound() async {
        await #expect(throws: CommandError.notFound("definitely-not-a-command")) {
            try await runner.run(Command("definitely-not-a-command", environment: environment))
        }
    }

    @Test func timeoutStopsTheCommand() async {
        await #expect(throws: CommandError.timedOut("sleep", after: .milliseconds(200))) {
            try await runner.run(Command("sleep", ["5"], environment: environment, timeout: .milliseconds(200)))
        }
    }

    /// Cancellation that arrives before launch used to call `terminate()` on a process that never ran,
    /// which raises an Objective-C exception and crashes the app.
    @Test func alreadyCancelledTaskDoesNotLaunch() async {
        let runner = runner
        let environment = environment
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.run(Command("sleep", ["5"], environment: environment))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancellationStopsARunningCommand() async {
        let runner = runner
        let environment = environment
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { try await runner.run(Command("sleep", ["5"], environment: environment)) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.now - start < .seconds(2))
    }

    /// Racing cancellation against launch must never crash, whichever side wins.
    @Test func cancellationRacingLaunchNeverCrashes() async {
        let runner = runner
        let environment = environment
        await withTaskGroup { group in
            for attempt in 0..<50 {
                let task = Task { try await runner.run(Command("true", environment: environment)) }
                group.addTask {
                    if attempt.isMultiple(of: 2) { await Task.yield() }
                    task.cancel()
                    _ = try? await task.value
                }
            }
        }
    }
}
#endif
