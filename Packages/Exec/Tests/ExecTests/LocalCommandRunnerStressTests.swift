#if os(macOS)
import Exec
import Foundation
import Testing

struct LocalCommandRunnerStressTests {
    @Test(arguments: 0..<4) func manyShortCommandsNeverTrap(_ child: Int) async {
        await #expect(processExitsWith: .success) {
            signal(SIGPIPE, SIG_IGN)
            await LocalCommandRunnerStress.run(commands: 2000, concurrency: 48)
        }
    }
}

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
        switch index % 8 {
        case 0, 1, 2:
            _ = try? await runner.run(Command("true", environment: environment))
        case 3, 4:
            _ = try? await runner.run(Command("sh", ["-c", "printf out; printf err >&2; exit 1"], environment: environment))
        case 5:
            _ = try? await runner.run(Command("true", environment: environment, standardInput: Data(repeating: 0, count: 256 * 1024)))
        case 6:
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
