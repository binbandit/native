#if os(macOS)
import Exec
import Foundation
import Testing

struct LocalCommandRunnerStressTests {
    /// libdispatch traps ("Unexpected EV_VANISHED") when a descriptor it is watching closes before the
    /// channel's cleanup handler runs. The pipe readers used to let their `FileHandle` close the
    /// descriptor as soon as the read finished, which crashed the app intermittently while many short
    /// git commands finished at once. The trap kills the process, so the load runs in a child.
    @Test func manyShortCommandsNeverTrap() async {
        await #expect(processExitsWith: .success) {
            signal(SIGPIPE, SIG_IGN); let s = ContinuousClock.now; await LocalCommandRunnerStress.run(commands: 3000, concurrency: 48); try? "took \(ContinuousClock.now - s)".write(toFile: "/tmp/execfix-child.txt", atomically: true, encoding: .utf8)
        }
    }
}

/// Short commands that end every way a command can: plain exits, output, input, failures,
/// cancellation and timeouts, so pipe descriptors close and their numbers get reused constantly.
private enum LocalCommandRunnerStress {
    static func run(commands: Int, concurrency: Int) async {
        let runner = LocalCommandRunner()
        let environment = ["PATH": "/usr/bin:/bin"]
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<commands {
                if index >= concurrency { await group.next() }
                group.addTask { await runOne(index, runner: runner, environment: environment) }
            }
        }
    }

    private static func runOne(_ index: Int, runner: LocalCommandRunner, environment: [String: String]) async {
        switch index % 6 {
        case 0:
            _ = try? await runner.run(Command("true", environment: environment))
        case 1:
            _ = try? await runner.run(Command("sh", ["-c", "printf out; printf err >&2; exit 1"], environment: environment))
        case 2:
            // Exits without reading its input.
            let input = Data(repeating: 0, count: 256 * 1024)
            _ = try? await runner.run(Command("true", environment: environment, standardInput: input))
        case 3:
            _ = try? await runner.run(Command("cat", environment: environment, standardInput: Data("in".utf8)))
        case 4:
            let task = Task { try await runner.run(Command("sleep", ["1"], environment: environment)) }
            if index.isMultiple(of: 4) { await Task.yield() }
            task.cancel()
            _ = try? await task.value
        default:
            _ = try? await runner.run(Command("sleep", ["1"], environment: environment, timeout: .milliseconds(5)))
        }
    }
}
#endif
