#if os(macOS)
import Exec
import Foundation
import Testing

extension ExecTests {
    /// Runs that crash end the process, so these run in child processes of their own.
    struct LocalCommandRunnerStressTests {
        /// The pipe readers used to let their `FileHandle` close each descriptor as soon as its read
        /// finished, while libdispatch was still watching it. With many short commands finishing at once,
        /// libdispatch then trapped ("Unexpected EV_VANISHED") and took the app down. The race is narrow,
        /// so this runs several batches, each in a process of its own.
        @Test(arguments: 0..<4) func manyShortCommandsNeverCrash(batch: Int) async {
            await #expect(processExitsWith: .success) {
                await LocalCommandRunnerStress.run(commands: 2000, concurrency: 48)
            }
        }

        /// Input for a command that exits without reading it used to raise SIGPIPE, which ends the
        /// process unless it ignores the signal, or the thread that wrote happens to block it. Repeated,
        /// since which thread writes varies.
        @Test func inputTheCommandNeverReadsIsHarmless() async {
            await #expect(processExitsWith: .success) {
                let command = Command(
                    "true", environment: ExecTests.environment, standardInput: Data(repeating: 0, count: 1 << 20))
                for _ in 0..<20 {
                    let result = try await LocalCommandRunner().run(command)
                    if !result.succeeded { exit(EXIT_FAILURE) }
                }
            }
        }
    }
}

/// Short commands that end every way a command can, mostly at once, so pipe descriptors close and
/// their numbers are reused constantly.
private enum LocalCommandRunnerStress {
    static func run(commands: Int, concurrency: Int) async {
        let runner = LocalCommandRunner()
        let environment = ExecTests.environment
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<commands {
                if index >= concurrency { await group.next() }
                group.addTask { await runOne(index, runner: runner, environment: environment) }
            }
        }
    }

    private static func runOne(_ index: Int, runner: LocalCommandRunner, environment: [String: String]) async {
        switch index % 10 {
        case 0..<4:
            _ = try? await runner.run(Command("true", environment: environment))
        case 4, 5:
            let script = "printf out; printf err >&2; exit 1"
            _ = try? await runner.run(Command("sh", ["-c", script], environment: environment))
        case 6:
            let input = Data(repeating: 0, count: 256 * 1024)
            _ = try? await runner.run(Command("true", environment: environment, standardInput: input))
        case 7:
            let task = Task { try await runner.run(Command("sleep", ["1"], environment: environment)) }
            if index.isMultiple(of: 4) { await Task.yield() }
            task.cancel()
            _ = try? await task.value
        case 8:
            let command = Command("sleep", ["1"], environment: environment, timeout: .milliseconds(5))
            _ = try? await runner.run(command)
        default:
            let command = Command("sh", ["-c", "printf x"], environment: environment, outputEndsAtExit: true)
            _ = try? await runner.run(command)
        }
    }
}
#endif
