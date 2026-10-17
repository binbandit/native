import Foundation

extension Repository {
    /// The main working tree first, then linked worktrees.
    public func worktrees() async throws(GitError) -> [Worktree] {
        let output = try await run(["worktree", "list", "--porcelain", "-z"], readOnly: true)
        return WorktreeParser.parse(output.text)
    }

    /// Creates a worktree at `path`, and any folders above it, on a new branch from `startPoint`.
    @discardableResult
    public func addWorktree(
        at path: URL, newBranch branch: String, startPoint: String = "HEAD"
    ) async throws(GitError) -> Worktree {
        try await run(["worktree", "add", "-b", branch, "--", path.path(percentEncoded: false), startPoint])
        return try await requireListedWorktree(at: path)
    }

    /// Gives a task its own worktree, Conductor-style, so parallel agents never edit the same
    /// checkout. The folder (`<location>/<repository>/<slug>`) and the branch (`<prefix><slug>`)
    /// get a numeric suffix when either is taken, locally or on a remote. `location` defaults to
    /// `~/.native/worktrees` in the home folder of the machine git runs on. A `detached` worktree
    /// gets no branch, for checking out something else in it (a pull request).
    public func createWorktree(
        forTask title: String,
        branchPrefix: String = "",
        startPoint: String = "HEAD",
        in location: URL? = nil,
        detached: Bool = false
    ) async throws(GitError) -> Worktree {
        let slug = Worktree.slug(title)
        let base = location ?? Worktree.defaultLocation(home: git.environment["HOME"])
        let repositoryFolder = base.appending(path: Worktree.slug(name, maxLength: 60), directoryHint: .isDirectory)
        let taken = try await takenBranchNames()
        let existing = Set(try await worktrees().map { Self.spelling(of: $0.path) })
        for attempt in 1...100 {
            let name = attempt == 1 ? slug : "\(slug)-\(attempt)"
            let path = repositoryFolder.appending(path: name, directoryHint: .isDirectory)
            let branch = branchPrefix + name
            guard !taken.contains(branch), !existing.contains(Self.spelling(of: path)) else { continue }
            let valid = try await run(
                ["check-ref-format", "--branch", branch], readOnly: true, acceptingStatus: [0, 1, 128])
            guard valid.status == 0 else {
                throw .failed(
                    arguments: ["check-ref-format", branch], status: valid.status,
                    stderr: "“\(branch)” isn't a valid branch name.")
            }
            do {
                if detached {
                    try await run(["worktree", "add", "--detach", "--", path.path(percentEncoded: false), startPoint])
                    return try await requireListedWorktree(at: path)
                }
                return try await addWorktree(at: path, newBranch: branch, startPoint: startPoint)
            } catch .failed(_, _, let stderr) where stderr.contains("already exists") {
                // A folder left at that path by something else; try the next name.
                continue
            }
        }
        throw .failed(arguments: ["worktree", "add"], status: 1, stderr: "Every worktree name for “\(slug)” is taken.")
    }

    /// Removes a linked worktree. Uncommitted work is checkpointed first unless `checkpoint` is
    /// false; with `force`, git removes it even when it has changes (safe once checkpointed).
    /// The branch stays, so its commits remain reachable. Returns the checkpoint, if one was made.
    @discardableResult
    public func removeWorktree(
        at path: URL, force: Bool = false, checkpoint: Bool = true
    ) async throws(GitError) -> Checkpoint? {
        let all = try await worktrees()
        guard let worktree = await listedWorktree(at: path, in: all) else {
            throw .failed(
                arguments: ["worktree", "remove"], status: 128,
                stderr: "\(path.path(percentEncoded: false)) isn't a worktree of this repository.")
        }
        guard !worktree.isMain else {
            throw .failed(
                arguments: ["worktree", "remove"], status: 128, stderr: "The main working tree can't be removed.")
        }
        // Run from the main working tree: a worktree can't remove itself from the inside.
        let main =
            all.first(where: \.isMain).map {
                Repository(git: git, root: $0.path, gitDirectory: commonDirectory, commonDirectory: commonDirectory)
            } ?? self

        guard !worktree.isPrunable else {
            // Its folder was deleted by hand; forget it.
            try await main.run(["worktree", "prune"])
            return nil
        }
        var saved: Checkpoint?
        if checkpoint, let repository = try await git.repository(at: worktree.path) {
            saved = try await repository.checkpoint(named: worktree.path.lastPathComponent)
        }
        var arguments = ["worktree", "remove"]
        if force { arguments.append("--force") }
        try await main.run(arguments + ["--", worktree.path.path(percentEncoded: false)])
        return saved
    }

    /// Brings back a removed worktree: checks `branch` out at `path` again and, with a
    /// checkpoint from `removeWorktree`, restores the uncommitted work it held.
    @discardableResult
    public func restoreWorktree(
        at path: URL, branch: String, from checkpoint: Checkpoint?
    ) async throws(GitError) -> Worktree {
        try await run(["worktree", "add", "--", path.path(percentEncoded: false), branch])
        let worktree = try await requireListedWorktree(at: path)
        if let checkpoint, let repository = try await git.repository(at: worktree.path) {
            try await repository.restore(checkpoint)
        }
        return worktree
    }

    // MARK: - Helpers

    /// Local and remote branch names; remote ones count so a first push never lands on someone
    /// else's branch.
    private func takenBranchNames() async throws(GitError) -> Set<String> {
        let refs = try await run(["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes"], readOnly: true)
        var taken: Set<String> = []
        for reference in refs.text.split(separator: "\n") {
            if reference.hasPrefix("refs/heads/") {
                taken.insert(String(reference.dropFirst("refs/heads/".count)))
            } else if let branch = reference.dropFirst("refs/remotes/".count).split(separator: "/", maxSplits: 1).last {
                taken.insert(String(branch))
            }
        }
        return taken
    }

    private func requireListedWorktree(at path: URL) async throws(GitError) -> Worktree {
        guard let worktree = await listedWorktree(at: path, in: try await worktrees()) else {
            throw .unexpectedOutput("The worktree at \(path.path(percentEncoded: false)) isn't listed.")
        }
        return worktree
    }

    /// The listed worktree at `path`, compared the way git spells paths (with symlinks such as
    /// `/tmp` resolved), which works whichever machine the repository is on.
    private func listedWorktree(at path: URL, in worktrees: [Worktree]) async -> Worktree? {
        var spellings: Set = [Self.spelling(of: path)]
        if let toplevel = await toplevel(of: path) {
            spellings.insert(toplevel)
        }
        return worktrees.first { spellings.contains(Self.spelling(of: $0.path)) }
    }

    /// A folder path without its trailing slash.
    private static func spelling(of url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
