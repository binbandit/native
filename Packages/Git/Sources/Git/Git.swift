import Exec
import Foundation

/// The user's `git`, run with their environment so their config, hooks, credential helpers and
/// signing keys all apply. Every command, and every look at the working tree, goes through a
/// `CommandRunner`, so a repository on another machine (a remote Native Host) works the same as
/// one on this Mac. Watching for changes goes through a `RepositoryMonitor` for the same reason.
///
/// Nothing here touches the network except `Repository.push()` and `pull()`.
public struct Git: Sendable {
    /// `git` to look up on the PATH, or an absolute path on the runner's machine.
    public let executable: String
    /// The environment git runs with: the user's login shell's, since GUI apps (and remote hosts)
    /// don't inherit a terminal's.
    public let environment: [String: String]
    public let runner: any CommandRunner
    public let monitor: any RepositoryMonitor

    public init(
        environment: [String: String],
        runner: any CommandRunner = LocalCommandRunner(),
        monitor: any RepositoryMonitor = FSEventsRepositoryMonitor(),
        executable: String = "git"
    ) {
        self.executable = executable
        self.runner = runner
        self.monitor = monitor
        // Variables a git hook would export to us; inherited, they'd point every command at the
        // wrong repository or index.
        let repositoryOverrides: Set = [
            "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_PREFIX", "GIT_OBJECT_DIRECTORY",
        ]
        self.environment = environment.filter { !repositoryOverrides.contains($0.key) }
    }

    /// The repository containing `folder`, or `nil` when it isn't inside a working tree.
    public func repository(at folder: URL) async throws(GitError) -> Repository? {
        let output = try await run(
            ["rev-parse", "--path-format=absolute", "--show-toplevel", "--git-dir", "--git-common-dir"],
            in: folder,
            readOnly: true,
            acceptingStatus: [0, 128]
        )
        // 128: not a repository, or inside `.git` where there's no working tree.
        guard output.status == 0 else { return nil }
        let lines = output.text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count == 3 else { throw .unexpectedOutput("rev-parse: \(output.text)") }
        return Repository(
            git: self,
            root: URL(filePath: lines[0], directoryHint: .isDirectory),
            gitDirectory: URL(filePath: lines[1], directoryHint: .isDirectory),
            commonDirectory: URL(filePath: lines[2], directoryHint: .isDirectory)
        )
    }

    /// Makes `folder` a repository with `git init`, honoring the user's `init.defaultBranch`.
    @discardableResult
    public func initializeRepository(at folder: URL) async throws(GitError) -> Repository {
        try await run(["init", "--quiet"], in: folder)
        guard let repository = try await repository(at: folder) else {
            throw .unexpectedOutput("git init didn't create a repository at \(folder.path(percentEncoded: false)).")
        }
        return repository
    }

    /// `git --version`, e.g. "2.47.1". Fails with `.gitNotFound` when git isn't installed.
    public func version() async throws(GitError) -> String {
        let output = try await run(["--version"], in: nil, readOnly: true)
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: "git version ", with: "")
    }

    // MARK: - Running

    struct Output: Sendable {
        var stdout: Data
        var stderr: String
        var status: Int32

        var text: String { String(decoding: stdout, as: UTF8.self) }
    }

    /// Runs git in `directory`. Read-only commands skip optional locks, so a background status
    /// refresh never holds `index.lock` while an agent runs git in the same repository.
    @discardableResult
    func run(
        _ arguments: [String],
        in directory: URL?,
        readOnly: Bool = false,
        input: Data? = nil,
        environment overrides: [String: String] = [:],
        acceptingStatus accepted: Set<Int32> = [0]
    ) async throws(GitError) -> Output {
        var environment = environment
        // Fail instead of waiting for a terminal that isn't there.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_EDITOR"] = "true"
        if readOnly {
            environment["GIT_OPTIONAL_LOCKS"] = "0"
        }
        environment.merge(overrides) { $1 }

        let output = try await execute(executable, arguments, in: directory, environment: environment, input: input)
        guard accepted.contains(output.status) else {
            // Some failures, like "nothing to commit", only go to stdout.
            let message = output.stderr.isEmpty ? String(output.text.prefix(4096)) : output.stderr
            throw .failed(arguments: arguments, status: output.status, stderr: message)
        }
        return output
    }

    /// Runs a plain tool (`cat`, `rm`, `cp`) on the same machine as git, for the few working tree
    /// operations git has no command for.
    func runTool(_ tool: String, _ arguments: [String], in directory: URL?) async throws(GitError) -> Output {
        try await execute(tool, arguments, in: directory, environment: environment, input: nil)
    }

    private func execute(
        _ executable: String,
        _ arguments: [String],
        in directory: URL?,
        environment: [String: String],
        input: Data?
    ) async throws(GitError) -> Output {
        let command = Command(
            executable,
            arguments,
            in: directory?.path(percentEncoded: false),
            environment: environment,
            standardInput: input
        )
        // A cancelled caller never starts a command: there's nothing to stop yet.
        if Task.isCancelled { throw .cancelled }
        let result: CommandResult
        do {
            result = try await runner.run(command)
        } catch CommandError.notFound where executable == self.executable {
            throw .gitNotFound
        } catch let error as CommandError {
            throw .launchFailed(error.localizedDescription)
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        // The runner stops the command when the task is cancelled; its output is incomplete.
        if Task.isCancelled { throw .cancelled }
        return Output(stdout: result.standardOutput, stderr: result.errorOutput, status: result.exitCode)
    }
}
