import Foundation

/// A git working tree: the main one or a linked worktree. Every method runs the user's git in
/// `root`; none of them touch the network except `push()`.
public struct Repository: Sendable, Hashable {
    public let git: Git
    /// The top of the working tree.
    public let root: URL
    /// This working tree's git directory (`.git`, or `.git/worktrees/<name>` for a linked worktree).
    public let gitDirectory: URL
    /// The directory shared by all worktrees: objects, refs and config.
    public let commonDirectory: URL

    public init(git: Git, root: URL, gitDirectory: URL, commonDirectory: URL) {
        self.git = git
        self.root = root
        self.gitDirectory = gitDirectory
        self.commonDirectory = commonDirectory
    }

    /// Whether this is a linked worktree rather than the main working tree.
    public var isLinkedWorktree: Bool {
        gitDirectory.standardizedFileURL != commonDirectory.standardizedFileURL
    }

    /// The project's name: the main working tree's folder, also when this is a linked worktree.
    public var name: String {
        let common = commonDirectory.standardizedFileURL
        // A bare repository's common directory is the repository itself.
        let main = common.lastPathComponent == ".git" ? common.deletingLastPathComponent() : common
        let name = main.lastPathComponent
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }

    // MARK: - Running

    @discardableResult
    func run(
        _ arguments: [String],
        readOnly: Bool = false,
        input: Data? = nil,
        environment: [String: String] = [:],
        acceptingStatus accepted: Set<Int32> = [0]
    ) async throws(GitError) -> Git.Output {
        try await git.run(
            arguments, in: root, readOnly: readOnly, input: input, environment: environment, acceptingStatus: accepted)
    }

    /// The commit `revision` names, or `nil` when it names nothing, like HEAD before the first
    /// commit.
    func resolve(_ revision: String) async throws(GitError) -> String? {
        let output = try await run(
            ["rev-parse", "--verify", "--quiet", revision], readOnly: true, acceptingStatus: [0, 1])
        return output.status == 0 ? output.text.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    /// Runs a command on literal paths fed through stdin, which sidesteps both pathspec magic
    /// (`*`, `:`) and argument length limits.
    func runWithPaths(
        _ arguments: [String], _ paths: [String], environment: [String: String] = [:]
    ) async throws(GitError) {
        var input = Data()
        for path in paths {
            input.append(contentsOf: path.utf8)
            input.append(0)
        }
        try await run(
            ["--literal-pathspecs"] + arguments + ["--pathspec-from-file=-", "--pathspec-file-nul"],
            input: input, environment: environment)
    }

    /// Runs `body` with `GIT_INDEX_FILE` pointing at a scratch index in the git directory, so the
    /// real index is never touched, and removes the scratch index afterwards. With `copyingIndex`
    /// the scratch starts as a copy of the real index.
    func withScratchIndex<Result>(
        copyingIndex: Bool,
        _ body: ([String: String]) async throws(GitError) -> Result
    ) async throws(GitError) -> Result {
        let scratch = gitDirectory.appending(path: "native-scratch-\(UUID().uuidString).index").path(
            percentEncoded: false)
        if copyingIndex {
            let index = try await run(["rev-parse", "--path-format=absolute", "--git-path", "index"], readOnly: true)
                .text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Before anything is staged there's no index to copy, and an empty scratch is right.
            _ = try await git.runTool("cp", ["--", index, scratch], in: root)
        }
        let result: Result
        do {
            result = try await body(["GIT_INDEX_FILE": scratch])
        } catch {
            // In a task of its own: a cancelled caller (a snapshot past its deadline) starts no
            // commands, and would leave the scratch index behind.
            let git = git
            let root = root
            await Task { _ = try? await git.runTool("rm", ["-f", "--", scratch], in: root) }.value
            throw error
        }
        _ = try await git.runTool("rm", ["-f", "--", scratch], in: root)
        return result
    }

    /// The top of the working tree at `path` as git spells it (symlinks resolved), or `nil` when
    /// there's no working tree there. Comparing git's own spellings works on any machine.
    func toplevel(of path: URL) async -> String? {
        guard let output = try? await git.run(["rev-parse", "--show-toplevel"], in: path, readOnly: true),
            output.status == 0
        else { return nil }
        return output.text.trimmingCharacters(in: .newlines)
    }

    public static func == (lhs: Repository, rhs: Repository) -> Bool {
        lhs.root == rhs.root && lhs.gitDirectory == rhs.gitDirectory
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(root)
        hasher.combine(gitDirectory)
    }
}
