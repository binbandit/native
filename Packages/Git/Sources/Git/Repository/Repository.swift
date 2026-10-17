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
        try await git.run(arguments, in: root, readOnly: readOnly, input: input, environment: environment, acceptingStatus: accepted)
    }

    /// Runs a command on literal paths fed through stdin, which sidesteps both pathspec magic
    /// (`*`, `:`) and argument length limits.
    func runWithPaths(_ arguments: [String], _ paths: [String]) async throws(GitError) {
        var input = Data()
        for path in paths {
            input.append(contentsOf: path.utf8)
            input.append(0)
        }
        try await run(["--literal-pathspecs"] + arguments + ["--pathspec-from-file=-", "--pathspec-file-nul"], input: input)
    }

    public static func == (lhs: Repository, rhs: Repository) -> Bool {
        lhs.root == rhs.root && lhs.gitDirectory == rhs.gitDirectory
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(root)
        hasher.combine(gitDirectory)
    }

    /// The path with symlinks resolved, e.g. `/tmp` to `/private/tmp`, for comparing with git's.
    static func canonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard let resolved = realpath(path, nil) else { return path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
