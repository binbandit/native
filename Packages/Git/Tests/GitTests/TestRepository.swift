import Exec
import Foundation
import Testing

@testable import Git

/// A throwaway repository in the temporary directory, isolated from the user's git config so
/// their hooks, signing and aliases can't affect the tests.
struct TestRepository {
    let folder: URL
    let git: Git

    static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        let emptyConfig = FileManager.default.temporaryDirectory.appending(path: "native-git-tests-empty.gitconfig")
        FileManager.default.createFile(atPath: emptyConfig.path(percentEncoded: false), contents: Data())
        environment["GIT_CONFIG_GLOBAL"] = emptyConfig.path(percentEncoded: false)
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_AUTHOR_NAME"] = "Test"
        environment["GIT_AUTHOR_EMAIL"] = "test@example.com"
        environment["GIT_COMMITTER_NAME"] = "Test"
        environment["GIT_COMMITTER_EMAIL"] = "test@example.com"
        return environment
    }()

    /// An empty folder; `initialize` makes it a repository.
    init(name: String = "repo", runner: any CommandRunner = LocalCommandRunner()) throws {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "native-git-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        folder = base.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        git = Git(environment: Self.environment, runner: runner, monitor: FSEventsRepositoryMonitor())
    }

    /// `git init` with a `main` branch, optionally committing a README.
    static func make(
        name: String = "repo", commit: Bool = true, runner: any CommandRunner = LocalCommandRunner()
    ) async throws -> TestRepository {
        let test = try TestRepository(name: name, runner: runner)
        try await test.git("init", "--quiet", "--initial-branch=main")
        if commit {
            try test.write("README.md", "# Test\n\nHello.\n")
            try await test.git("add", "README.md")
            try await test.git("commit", "--quiet", "-m", "Initial commit")
        }
        return test
    }

    var repository: Repository {
        get async throws {
            try #require(await git.repository(at: folder))
        }
    }

    @discardableResult
    func git(_ arguments: String..., in directory: URL? = nil) async throws -> String {
        try await git.run(arguments, in: directory ?? folder).text
    }

    func write(_ path: String, _ contents: String) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: folder.appending(path: path), encoding: .utf8)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: path).path(percentEncoded: false))
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }
}
