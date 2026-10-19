#if os(macOS)
import Exec
import Foundation
import Synchronization
import Testing

extension ExecTests {
    struct LocalCommandRunnerTests {
        private let runner = LocalCommandRunner()
        private let environment = ExecTests.environment

        @Test func capturesOutputErrorAndExitCode() async throws {
            let result = try await runner.run(
                Command("sh", ["-c", "printf out; printf err >&2; exit 3"], environment: environment))
            #expect(result.exitCode == 3)
            #expect(result.output == "out")
            #expect(result.errorOutput == "err")
        }

        @Test func passesInputDirectoryAndEnvironment() async throws {
            let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path(percentEncoded: false)
            let result = try await runner.run(
                Command(
                    "sh",
                    ["-c", "cat; printf \" $GREETING \"; pwd"],
                    in: directory,
                    environment: environment.merging(["GREETING": "hi"]) { $1 },
                    standardInput: Data("input".utf8)
                ))
            #expect(result.output.hasPrefix("input hi "))
            #expect(
                result.output.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(
                    directory.trimmingCharacters(in: ["/"])))
        }

        /// More output than a pipe buffer holds must not deadlock.
        @Test func drainsLargeOutput() async throws {
            let result = try await runner.run(
                Command("sh", ["-c", "head -c 1000000 /dev/zero"], environment: environment))
            #expect(result.standardOutput.count == 1_000_000)
        }

        @Test func missingExecutableIsNotFound() async {
            await #expect(throws: CommandError.notFound("definitely-not-a-command")) {
                try await runner.run(Command("definitely-not-a-command", environment: environment))
            }
        }

        @Test func timeoutStopsTheCommand() async {
            await #expect(throws: CommandError.timedOut("sleep", after: .milliseconds(200))) {
                try await runner.run(Command("sleep", ["30"], environment: environment, timeout: .milliseconds(200)))
            }
        }

        /// A shell killed for running too long used to leave its children holding the output open, so the
        /// run waited for them instead of stopping.
        @Test func timeoutStopsWhatTheCommandStarted() async {
            let clock = ContinuousClock()
            let start = clock.now
            await #expect(throws: CommandError.timedOut("sh", after: .milliseconds(300))) {
                try await runner.run(
                    Command(
                        "sh", ["-c", "echo started; sleep 30; echo never"], environment: environment,
                        timeout: .milliseconds(300)))
            }
            #expect(clock.now - start < .seconds(10))
        }

        /// A stopped command's process group used to be killed only while the command itself still ran,
        /// so what it started and that ignored the request to stop outlived it, holding the output open,
        /// and the run waited for it.
        @Test func stopKillsWhatOutlivesTheCommand() async {
            let clock = ContinuousClock()
            let start = clock.now
            let script = "(trap '' TERM; exec sleep 30) & echo started; wait"
            await #expect(throws: CommandError.timedOut("sh", after: .milliseconds(300))) {
                try await runner.run(
                    Command("sh", ["-c", script], environment: environment, timeout: .milliseconds(300)))
            }
            #expect(clock.now - start < .seconds(15))
        }

        /// Input used to be written before the timeout started, blocking for as long as the command
        /// didn't read it, so a command that never read its input could outlive its timeout.
        @Test func timeoutStopsACommandThatIgnoresItsInput() async {
            let clock = ContinuousClock()
            let start = clock.now
            await #expect(throws: CommandError.timedOut("sleep", after: .milliseconds(200))) {
                try await runner.run(
                    Command(
                        "sleep", ["30"], environment: environment, standardInput: Data(repeating: 0, count: 1 << 20),
                        timeout: .milliseconds(200)))
            }
            #expect(clock.now - start < .seconds(10))
        }

        /// A process started meanwhile by something other than `Process` inherits every descriptor that
        /// isn't close-on-exec. Holding the command's input open, it kept the command from ever seeing
        /// the end of it.
        @Test func inputEndsEvenIfAnotherProcessStartsMeanwhile() async throws {
            let flag = ExecTests.flagPath()
            defer { try? FileManager.default.removeItem(atPath: flag) }
            // The command reads nothing until the flag exists, so the input is still being written.
            let script = "printf started; while [ ! -e \"$FLAG\" ]; do sleep 0.05; done; wc -c"
            let command = Command(
                "sh", ["-c", script], environment: environment.merging(["FLAG": flag]) { $1 },
                standardInput: Data(repeating: 0, count: 1 << 20), timeout: .seconds(20))
            let (started, starting) = AsyncStream.makeStream(of: Void.self)
            let runner = runner
            let run = Task { try await runner.run(command) { _ in starting.yield() } }
            for await _ in started { break }
            let inheritor = try ExecTests.spawnInheritingDescriptors()
            defer { ExecTests.reap(inheritor) }
            FileManager.default.createFile(atPath: flag, contents: nil)
            let result = try await run.value
            #expect(result.output.hasSuffix("1048576\n"))
        }

        /// The command finishes only once its first output has been handed over, so a runner that held
        /// output back until the end would time out instead.
        @Test func streamsOutputAsItArrives() async throws {
            let flag = ExecTests.flagPath()
            defer { try? FileManager.default.removeItem(atPath: flag) }
            let chunks = Mutex<[CommandOutput]>([])
            let script = "printf one; while [ ! -e \"$FLAG\" ]; do sleep 0.05; done; printf two >&2"
            let result = try await runner.run(
                Command(
                    "sh", ["-c", script], environment: environment.merging(["FLAG": flag]) { $1 },
                    timeout: .seconds(20))
            ) { chunk in
                chunks.withLock { $0.append(chunk) }
                FileManager.default.createFile(atPath: flag, contents: nil)
            }
            let streamed = chunks.withLock { $0 }
            #expect(streamed.filter { $0.stream == .standardOutput }.map(\.data).reduce(Data(), +) == Data("one".utf8))
            #expect(streamed.filter { $0.stream == .standardError }.map(\.data).reduce(Data(), +) == Data("two".utf8))
            #expect(result.output == "one")
            #expect(result.errorOutput == "two")
        }

        /// A setup script that starts a server in the background is done when it exits.
        @Test func outputCanEndAtExit() async throws {
            let clock = ContinuousClock()
            let start = clock.now
            let result = try await runner.run(
                Command("sh", ["-c", "sleep 10 & echo done"], environment: environment, outputEndsAtExit: true))
            #expect(result.output == "done\n")
            #expect(clock.now - start < .seconds(5))
        }

        /// Under parallel load, output that arrived while the pipes were being drained used to go missing.
        @Test func parallelCommandsKeepEveryByte() async throws {
            let runner = runner
            let environment = environment
            let script = "head -c 100000 /dev/zero | tr '\\0' x; printf err >&2"
            try await withThrowingTaskGroup { group in
                for _ in 0..<50 {
                    group.addTask { try await runner.run(Command("sh", ["-c", script], environment: environment)) }
                }
                for try await result in group {
                    #expect(result.standardOutput == Data(repeating: UInt8(ascii: "x"), count: 100_000))
                    #expect(result.errorOutput == "err")
                }
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
            let task = Task { try await runner.run(Command("sleep", ["30"], environment: environment)) }
            try? await Task.sleep(for: .milliseconds(100))
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(clock.now - start < .seconds(10))
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
}
#endif
