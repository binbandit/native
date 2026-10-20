import Foundation
import Synchronization
import Testing

@testable import Git

@Suite("Watching a repository on a host")
struct HostRepositoryMonitorTests {
    /// A host's watcher the test drives: it records the folders asked for and sends what it's told.
    final class ScriptedHost: Sendable {
        private let watches = Mutex<[String: AsyncStream<HostRepositoryMonitor.Batch>.Continuation]>([:])

        var monitor: HostRepositoryMonitor {
            HostRepositoryMonitor { self.watch($0) }
        }

        private func watch(_ folder: String) -> AsyncStream<HostRepositoryMonitor.Batch> {
            let (stream, continuation) = AsyncStream.makeStream(of: HostRepositoryMonitor.Batch.self)
            continuation.onTermination = { [weak self] _ in self?.watches.withLock { $0[folder] = nil } }
            watches.withLock { $0[folder] = continuation }
            return stream
        }

        var folders: Set<String> { watches.withLock { Set($0.keys) } }

        func send(_ paths: [String], isOverflow: Bool = false, under folder: String) {
            _ = watches.withLock { $0[folder] }?.yield(
                HostRepositoryMonitor.Batch(paths: paths, isOverflow: isOverflow))
        }

        func waitForWatches(_ count: Int) async throws {
            for _ in 0..<500 where folders.count != count {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// A repository as a host's git reported it: none of these paths exist on this machine.
    private func repository(root: String, gitDirectory: String, commonDirectory: String) -> Repository {
        Repository(
            git: Git(environment: [:]), root: URL(filePath: root, directoryHint: .isDirectory),
            gitDirectory: URL(filePath: gitDirectory, directoryHint: .isDirectory),
            commonDirectory: URL(filePath: commonDirectory, directoryHint: .isDirectory))
    }

    @Test("The host's raw paths are sorted like FSEvents' here: files, git state that matters, noise")
    func classifies() async throws {
        let host = ScriptedHost()
        let repository = repository(
            root: "/srv/repo", gitDirectory: "/srv/repo/.git", commonDirectory: "/srv/repo/.git")
        var changes = host.monitor.changes(in: repository).makeAsyncIterator()
        try await host.waitForWatches(1)
        #expect(host.folders == ["/srv/repo"])

        host.send(["/srv/repo/.git/objects/ab/cdef"], under: "/srv/repo")
        host.send(
            ["/srv/repo/src/a.swift", "/srv/repo/.git/index", "/srv/repo/.git/objects/12/3456"], under: "/srv/repo")
        #expect(await changes.next() == RepositoryChange(paths: ["src/a.swift"], gitStateChanged: true))

        host.send([], isOverflow: true, under: "/srv/repo")
        #expect(await changes.next() == RepositoryChange(paths: [], gitStateChanged: true))
    }

    @Test("A linked worktree's git folders are watched too, and stopping ends every watch")
    func linkedWorktree() async throws {
        let host = ScriptedHost()
        let repository = repository(
            root: "/srv/worktrees/task", gitDirectory: "/srv/repo/.git/worktrees/task",
            commonDirectory: "/srv/repo/.git")
        let following = Task {
            var changes: [RepositoryChange] = []
            for await change in host.monitor.changes(in: repository) {
                changes.append(change)
                if changes.count == 2 { break }
            }
            return changes
        }
        try await host.waitForWatches(3)
        #expect(host.folders == ["/srv/worktrees/task", "/srv/repo/.git/worktrees/task", "/srv/repo/.git"])

        host.send(["/srv/repo/.git/refs/heads/main"], under: "/srv/repo/.git")
        try await Task.sleep(for: .milliseconds(50))
        host.send(["/srv/worktrees/task/notes.md"], under: "/srv/worktrees/task")
        let changes = await following.value
        #expect(changes.contains(RepositoryChange(paths: [], gitStateChanged: true)))
        #expect(changes.contains(RepositoryChange(paths: ["notes.md"], gitStateChanged: false)))
        try await host.waitForWatches(0)
        #expect(host.folders.isEmpty)
    }
}
