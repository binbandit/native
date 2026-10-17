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
}
#endif
