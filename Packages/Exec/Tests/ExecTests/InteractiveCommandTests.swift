import Foundation
import Testing

@testable import Exec

@Suite("Interactive command input")
struct InteractiveCommandTests {
    @Test func terminalInputArrivesAfterPromptWithoutEcho() async throws {
        let input = CommandInput()
        let command = Command(
            "/bin/sh",
            [
                "-c",
                "test -t 0 && test -t 1 || exit 7; printf 'ready\\n'; read -r reply; test \"$reply\" = 'private-code'",
            ],
            environment: [:], timeout: .seconds(5))
        let result = try await LocalCommandRunner().run(command, input: input) { output in
            if String(decoding: output.data, as: UTF8.self).contains("ready") {
                input.send(Data("private-code\n".utf8))
            }
        }
        #expect(result.succeeded)
        #expect(result.output.replacingOccurrences(of: "\r", with: "") == "ready\n")
        #expect(result.errorOutput.isEmpty)
    }

    @Test func waitingForInputTimesOut() async throws {
        let command = Command("/bin/sh", ["-c", "read -r reply"], environment: [:], timeout: .milliseconds(100))
        await #expect(throws: CommandError.timedOut("/bin/sh", after: .milliseconds(100))) {
            _ = try await LocalCommandRunner().run(command, input: CommandInput()) { _ in }
        }
    }

    @Test func failedLaunchClosesTerminal() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path
        await #expect(throws: (any Error).self) {
            _ = try await LocalCommandRunner().run(
                Command("/bin/sh", ["-c", "exit 0"], in: directory, environment: [:]), input: CommandInput()
            ) { _ in }
        }
    }

    @Test func cancelWhileWaitingForInput() async throws {
        let input = CommandInput()
        let (ready, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await LocalCommandRunner().run(
                Command("/bin/sh", ["-c", "echo ready; read -r reply"], environment: [:]), input: input
            ) { _ in continuation.yield(()) }
        }
        for await _ in ready { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
