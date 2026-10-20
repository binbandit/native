import Exec
import Foundation
import Git
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite("Git through a host", .timeLimit(.minutes(1)))
struct RemoteGitTests {
    /// Watching belongs to the change feed, not to these tests.
    private struct NoMonitor: RepositoryMonitor {
        func changes(in repository: Repository) -> AsyncStream<RepositoryChange> {
            AsyncStream { $0.finish() }
        }
    }

    @Test("The Git package runs unchanged against a repository on a host")
    func gitThroughTheHost() async throws {
        let host = try await ExecHost.make()
        let laptop = try await host.connect(ExecHost.commandingDevice, name: "laptop")
        // Nothing of this machine's environment travels: the host's own git setup applies.
        let git = Git(environment: [:], runner: RemoteCommandRunner(client: laptop), monitor: NoMonitor())
        #expect(try await !git.version().isEmpty)

        let repository = try await git.initializeRepository(at: host.project)
        try Data("# App\n".utf8).write(to: host.project.appending(path: "README.md"))
        let status = try await repository.status()
        #expect(status.changes.map(\.path) == ["README.md"])
        #expect(status.totals.additions == 1)

        // Committing writes the message to git's input.
        try await repository.commit(message: "Initial commit", files: status.changes)
        #expect(try await repository.recentCommitSubjects() == ["Initial commit"])
        #expect(try await repository.status().changes.isEmpty)

        // Outside the host's projects, git is refused like any command.
        await #expect(throws: GitError.self) { _ = try await git.repository(at: host.outside) }
        await laptop.stop()
        await host.stop()
    }
}
