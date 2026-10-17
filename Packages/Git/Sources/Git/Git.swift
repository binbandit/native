import Foundation

/// The user's `git`, run with their environment so their config, hooks, credential helpers and
/// signing keys all apply. GUI apps don't inherit a terminal's PATH, so callers pass the login
/// shell's environment and the executable is looked up on its PATH.
///
/// Nothing here touches the network except `Repository.push()`.
public struct Git: Sendable, Hashable {
    public let executableURL: URL
    public let environment: [String: String]

    /// Finds `git` on `environment`'s PATH.
    public init(environment: [String: String]) throws(GitError) {
        guard let executable = Self.locate(in: environment) else { throw .gitNotFound }
        self.init(executableURL: executable, environment: environment)
    }

    public init(executableURL: URL, environment: [String: String]) {
        self.executableURL = executableURL
        // Variables a git hook would export to us; inherited, they'd point every command at the
        // wrong repository or index.
        let repositoryOverrides: Set = [
            "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_PREFIX", "GIT_OBJECT_DIRECTORY",
        ]
        self.environment = environment.filter { !repositoryOverrides.contains($0.key) }
    }

    /// The first executable `git` on the PATH in `environment`.
    public static func locate(in environment: [String: String]) -> URL? {
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let fileManager = FileManager.default
        for directory in path.split(separator: ":") where !directory.isEmpty {
            let candidate = URL(filePath: String(directory)).appending(path: "git")
            if fileManager.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return nil
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

    /// `git --version`, e.g. "2.47.1".
    public func version() async throws(GitError) -> String {
        let output = try await run(["--version"], in: FileManager.default.temporaryDirectory, readOnly: true)
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
        in directory: URL,
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

        let output: Output
        do {
            output = try await Self.launch(
                executableURL, arguments: arguments, in: directory, environment: environment, input: input)
        } catch let error as GitError {
            throw error
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        guard accepted.contains(output.status) else {
            // Some failures, like "nothing to commit", only go to stdout.
            let message = output.stderr.isEmpty ? String(output.text.prefix(4096)) : output.stderr
            throw .failed(arguments: arguments, status: output.status, stderr: message)
        }
        return output
    }

    private static func launch(
        _ executable: URL,
        arguments: [String],
        in directory: URL,
        environment: [String: String],
        input: Data?
    ) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = input.map { _ in Pipe() }
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin ?? FileHandle.nullDevice

        let output: Output = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Blocking reads on GCD threads rather than the cooperative pool. Both pipes drain
                // at once so neither can fill up and stall git.
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: GitError.launchFailed(error.localizedDescription))
                        return
                    }
                    if let input, let stdin {
                        DispatchQueue.global(qos: .userInitiated).async {
                            try? stdin.fileHandleForWriting.write(contentsOf: input)
                            try? stdin.fileHandleForWriting.close()
                        }
                    }
                    let errors = PipeDrain(stderr.fileHandleForReading)
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errors.wait()
                    process.waitUntilExit()
                    continuation.resume(
                        returning: Output(
                            stdout: data,
                            stderr: String(decoding: errorData, as: UTF8.self),
                            status: process.terminationStatus
                        ))
                }
            }
        } onCancel: {
            // git cleans up its lock files on SIGTERM.
            if process.isRunning { process.terminate() }
        }
        if Task.isCancelled { throw GitError.cancelled }
        return output
    }
}

/// Reads a pipe to its end on a background thread.
private final class PipeDrain: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    // Written once before `done` is signaled, read only after waiting on it.
    private var data = Data()

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            data = handle.readDataToEndOfFile()
            done.signal()
        }
    }

    func wait() -> Data {
        done.wait()
        return data
    }
}
