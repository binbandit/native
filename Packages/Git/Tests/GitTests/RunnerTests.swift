import Exec
import Foundation
import Git
import Synchronization
import Testing

@Suite("Commands go through the injected runner")
struct RunnerTests {
    /// Runs commands locally and records what ran, standing in for a remote host's runner.
    final class RecordingRunner: CommandRunner {
        let commands = Mutex<[Command]>([])
        private let local = LocalCommandRunner()

        func run(_ command: Command) async throws -> CommandResult {
            commands.withLock { $0.append(command) }
            return try await local.run(command)
        }
    }

    @Test func statusDiffsAndDiscardUseTheRunner() async throws {
        let runner = RecordingRunner()
        let test = try await TestRepository.make(runner: runner)
        defer { test.remove() }
        let repository = try await test.repository
        try test.write("README.md", "# Changed\n")
        try test.write("new file.txt", "one\ntwo\n")
        runner.commands.withLock { $0.removeAll() }

        let status = try await repository.status()
        let untracked = try #require(status.untracked.first)
        let versions = try await repository.versions(of: untracked)
        try await repository.discard(status.changes)

        #expect(untracked.stats == LineStats(additions: 2))
        #expect(versions.newText == "one\ntwo\n")
        let executables = Set(runner.commands.withLock { $0.map(\.executable) })
        #expect(executables.isSubset(of: ["git", "sh", "rm", "cp"]))
        #expect(runner.commands.withLock { $0.allSatisfy { $0.environment["GIT_CONFIG_NOSYSTEM"] == "1" } })
        // Scratch indexes are cleaned up.
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: repository.gitDirectory.path(percentEncoded: false)
        )
        .filter { $0.hasPrefix("native-scratch-") }
        #expect(leftovers.isEmpty)
    }

    @Test func cancelledCallersDontStartCommands() async throws {
        let runner = RecordingRunner()
        let test = try await TestRepository.make(runner: runner)
        defer { test.remove() }
        let repository = try await test.repository
        runner.commands.withLock { $0.removeAll() }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.status()
        }

        await #expect(throws: GitError.cancelled) { try await task.value }
        let ran = runner.commands.withLock { $0.count }
        #expect(ran == 0)
    }

    @Test func missingGitIsReported() async throws {
        let git = Git(environment: ["PATH": "/nonexistent"])
        await #expect(throws: GitError.gitNotFound) { try await git.version() }
    }

    @Test func discardRefusesNestedRepositories() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let nested = FileChange(path: "vendor/lib/", kind: .untracked, area: .untracked)

        await #expect(throws: GitError.self) { try await repository.discard([nested]) }
    }
}
