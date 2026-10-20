import Foundation

// What a stretch of work changed, committed or not: snapshot the working tree when it starts, then
// compare that snapshot with one taken now, or with any commit (`git diff-tree`). Snapshots are
// loose objects only, never a ref or an index entry, so they stay out of the user's sight.
extension Repository {
    /// The working tree as it is now (`WorkingTreeSnapshot`), written through a scratch copy of the
    /// index: the real index, the refs and the files are left alone. Cancelling it stops git.
    public func snapshot() async throws(GitError) -> WorkingTreeSnapshot {
        let head = try await resolve("HEAD")
        let tree = try await withScratchIndex(copyingIndex: true) { scratch throws(GitError) in
            // Starting from a copy of the index, `add` only rehashes what changed since it was written.
            try await run(["add", "--all"], environment: scratch)
            return try await run(["write-tree"], environment: scratch).text.trimmingCharacters(
                in: .whitespacesAndNewlines)
        }
        return WorkingTreeSnapshot(head: head, tree: tree)
    }

    /// How many files git doesn't track and doesn't ignore: what a snapshot has to read and store
    /// on top of the tracked changes. Lists them without reading them.
    public func untrackedFileCount() async throws(GitError) -> Int {
        let output = try await run(["ls-files", "--others", "--exclude-standard", "-z"], readOnly: true)
        return output.stdout.count { $0 == 0 }
    }

    /// HEAD's commit, or nil before the first commit.
    public func headCommit() async throws(GitError) -> String? {
        try await resolve("HEAD")
    }

    /// Whether the repository still has an object, e.g. a snapshot's tree that garbage collection
    /// may have pruned.
    public func hasObject(_ id: String) async throws(GitError) -> Bool {
        try await run(["cat-file", "-e", id], readOnly: true, acceptingStatus: [0, 1, 128]).status == 0
    }

    /// The commit HEAD pointed at `date`: from this working tree's reflog, or, without one, the
    /// last commit before then on HEAD's first-parent history. Nil when there was none.
    public func head(at date: Date) async throws(GitError) -> String? {
        let seconds = Int(date.timeIntervalSince1970.rounded(.down))
        if let commit = try await resolve("HEAD@{@\(seconds)}") { return commit }
        let output = try await run(
            ["rev-list", "-1", "--first-parent", "--before=@\(seconds)", "HEAD"], readOnly: true,
            acceptingStatus: [0, 128])
        let commit = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.status == 0 && !commit.isEmpty ? commit : nil
    }

    /// Every file that differs between `base` and `target`, commits or trees (a snapshot's), with
    /// line counts, sorted by path. `nil` for `base` compares with the empty tree.
    public func treeChanges(from base: String?, to target: String) async throws(GitError) -> [TreeChange] {
        let base = if let base { base } else { try await emptyTree() }
        let common = ["diff-tree", "-r", "-M", "-z", "--no-ext-diff", "--no-textconv", base, target]
        var changes: [TreeChange]
        let stats: [String: LineStats]
        do {
            async let numstat = run(common + ["--numstat"], readOnly: true)
            changes = try RawDiffParser.parse(try await run(common + ["--raw"], readOnly: true).text)
            stats = NumstatParser.parse(try await numstat.text)
        } catch {
            throw error as? GitError ?? .unexpectedOutput("\(error)")
        }
        for index in changes.indices {
            changes[index].stats = stats[changes[index].path]
        }
        return changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// A file's bytes in a commit or tree, or `nil` when it doesn't exist there.
    public func contents(of path: String, in treeish: String) async throws(GitError) -> Data? {
        let output = try await run(
            ["cat-file", "blob", "\(treeish):\(path)"], readOnly: true, acceptingStatus: [0, 128])
        return output.status == 0 ? output.stdout : nil
    }

    /// The two sides of a change between `base` and `target`, read at the same time.
    public func versions(
        of change: TreeChange, from base: String?, to target: String
    ) async throws(GitError)
        -> FileVersions
    {
        let oldPath = change.kind == .added ? nil : change.originalPath ?? change.path
        let newPath = change.kind == .deleted ? nil : change.path
        do {
            async let old = contents(of: oldPath, in: base)
            async let new = contents(of: newPath, in: target)
            return FileVersions(path: change.path, old: try await old, new: try await new)
        } catch {
            throw error as? GitError ?? .unexpectedOutput("\(error)")
        }
    }

    private func contents(of path: String?, in treeish: String?) async throws(GitError) -> Data? {
        guard let path, let treeish else { return nil }
        return try await contents(of: path, in: treeish)
    }

    /// Where the checked-out branch's own work begins (`BranchBase`), or `nil` when there's
    /// nothing to compare it with: no commits, no default branch, or the default branch itself
    /// with no upstream.
    public func branchBase() async throws(GitError) -> BranchBase? {
        guard try await resolve("HEAD") != nil, let main = try await defaultBranch() else { return nil }
        let current = try await run(
            ["symbolic-ref", "--quiet", "--short", "HEAD"], readOnly: true, acceptingStatus: [0, 1])
        let branch = current.status == 0 ? current.text.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let compared: String
        if branch == main.local {
            // On the default branch, its own work is what the remote doesn't have yet.
            let upstream = try await run(
                ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], readOnly: true,
                acceptingStatus: [0, 128])
            guard upstream.status == 0 else { return nil }
            compared = upstream.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            compared = main.compared
        }
        let mergeBase = try await run(["merge-base", "HEAD", compared], readOnly: true, acceptingStatus: [0, 1])
        let commit = mergeBase.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mergeBase.status == 0, !commit.isEmpty else { return nil }
        return BranchBase(commit: commit, name: compared)
    }

    /// The default branch's local name and what to compare with: the remote's copy when there is
    /// one (`origin/HEAD`, else its `main` or `master`), else the local `main` or `master`.
    private func defaultBranch() async throws(GitError) -> (local: String, compared: String)? {
        let remotes = try await remotes()
        if let remote = remotes.contains("origin") ? "origin" : remotes.first {
            let head = try await run(
                ["symbolic-ref", "--quiet", "--short", "refs/remotes/\(remote)/HEAD"], readOnly: true,
                acceptingStatus: [0, 1, 128])
            let name = head.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if head.status == 0, name.hasPrefix("\(remote)/") {
                return (String(name.dropFirst(remote.count + 1)), name)
            }
            for local in ["main", "master"] {
                if try await resolve("refs/remotes/\(remote)/\(local)") != nil { return (local, "\(remote)/\(local)") }
            }
        }
        for local in ["main", "master"] {
            if try await resolve("refs/heads/\(local)") != nil { return (local, local) }
        }
        return nil
    }
}
