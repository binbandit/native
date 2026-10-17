import Foundation

extension Repository {
    /// The main working tree first, then linked worktrees.
    public func worktrees() async throws(GitError) -> [Worktree] {
        let output = try await run(["worktree", "list", "--porcelain", "-z"], readOnly: true)
        return WorktreeParser.parse(output.text)
    }

    /// Creates a worktree at `path` on a new branch from `startPoint`.
    @discardableResult
    public func addWorktree(
        at path: URL, newBranch branch: String, startPoint: String = "HEAD"
    ) async throws(GitError) -> Worktree {
        let parent = path.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw .launchFailed("Couldn't create \(parent.path(percentEncoded: false)): \(error.localizedDescription)")
        }
        try await run(["worktree", "add", "-b", branch, "--", path.path(percentEncoded: false), startPoint])
        let created = Self.canonicalPath(path)
        guard let worktree = try await worktrees().first(where: { Self.canonicalPath($0.path) == created }) else {
            throw .unexpectedOutput("The new worktree at \(path.path(percentEncoded: false)) isn't listed.")
        }
        return worktree
    }

    /// Gives a task its own worktree, Conductor-style, so parallel agents never edit the same
    /// checkout. The folder (`<location>/<repository>/<slug>`) and the branch (`<prefix><slug>`) get a
    /// numeric suffix when either is taken, locally or on a remote.
    public func createWorktree(
        forTask title: String,
        branchPrefix: String = "",
        startPoint: String = "HEAD",
        in location: URL = Worktree.defaultLocation
    ) async throws(GitError) -> Worktree {
        let slug = Worktree.slug(title)
        let repositoryFolder = location.appending(path: Worktree.slug(name, maxLength: 60), directoryHint: .isDirectory)
        // Remote branch names count too, so the first push doesn't land on someone else's branch.
        let refs = try await run(["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes"], readOnly: true)
        var taken: Set<String> = []
        for reference in refs.text.split(separator: "\n") {
            if reference.hasPrefix("refs/heads/") {
                taken.insert(String(reference.dropFirst("refs/heads/".count)))
            } else if let remoteBranch = reference.dropFirst("refs/remotes/".count).split(separator: "/", maxSplits: 1)
                .last
            {
                taken.insert(String(remoteBranch))
            }
        }
        let fileManager = FileManager.default
        for attempt in 1...100 {
            let name = attempt == 1 ? slug : "\(slug)-\(attempt)"
            let path = repositoryFolder.appending(path: name, directoryHint: .isDirectory)
            let branch = branchPrefix + name
            guard !taken.contains(branch), !fileManager.fileExists(atPath: path.path(percentEncoded: false)) else {
                continue
            }
            let valid = try await run(
                ["check-ref-format", "--branch", branch], readOnly: true, acceptingStatus: [0, 1, 128])
            guard valid.status == 0 else {
                throw .failed(
                    arguments: ["check-ref-format", branch], status: valid.status,
                    stderr: "“\(branch)” isn't a valid branch name.")
            }
            return try await addWorktree(at: path, newBranch: branch, startPoint: startPoint)
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
        let target = Self.canonicalPath(path)
        guard let worktree = all.first(where: { Self.canonicalPath($0.path) == target }) else {
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

        guard FileManager.default.fileExists(atPath: worktree.path.path(percentEncoded: false)) else {
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
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .launchFailed(
                "Couldn't create \(path.deletingLastPathComponent().path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
        try await run(["worktree", "add", "--", path.path(percentEncoded: false), branch])
        let restored = Self.canonicalPath(path)
        guard let worktree = try await worktrees().first(where: { Self.canonicalPath($0.path) == restored }) else {
            throw .unexpectedOutput("The restored worktree at \(path.path(percentEncoded: false)) isn't listed.")
        }
        if let checkpoint, let repository = try await git.repository(at: worktree.path) {
            try await repository.restore(checkpoint)
        }
        return worktree
    }
}
