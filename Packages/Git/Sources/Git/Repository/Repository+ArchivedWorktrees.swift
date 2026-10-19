import Foundation

/// Task worktrees Native removed when their tasks were archived, recorded in the repository's config
/// as `[nativeArchivedWorktree "<path>"]` with the branch and checkpoint ref. The record is written
/// before anything is removed and forgotten only once the worktree is back, so unarchiving works
/// after Native quits and relaunches, including in the middle of either step.
extension Repository {
    /// Records a task worktree about to be removed. Run it on the main working tree, after
    /// checkpointing the worktree and before removing it. A record left for the same folder by an
    /// earlier archive is replaced.
    public func recordArchivedWorktree(_ worktree: ArchivedWorktree) async throws(GitError) {
        try await forgetArchivedWorktree(at: worktree.path)
        let section = Self.archivedWorktreeSection(worktree.path)
        try await run(["config", "\(section).branch", worktree.branch])
        if let checkpoint = worktree.checkpoint {
            try await run(["config", "\(section).checkpoint", checkpoint.reference])
        }
    }

    /// The recorded worktrees that haven't been brought back, by path.
    public func archivedWorktrees() async throws(GitError) -> [ArchivedWorktree] {
        // 1: nothing is recorded. With -z each entry is "name\nvalue\0", so paths may hold spaces.
        let output = try await run(
            ["config", "-z", "--get-regexp", "^\(Self.archivedWorktreeConfigSection.lowercased())\\."], readOnly: true,
            acceptingStatus: [0, 1])
        let prefix = Self.archivedWorktreeConfigSection.lowercased() + "."
        var branches: [String: String] = [:]
        var checkpoints: [String: String] = [:]
        for entry in output.text.split(separator: "\0") {
            let parts = entry.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].hasPrefix(prefix), let dot = parts[0].lastIndex(of: ".") else { continue }
            let name = parts[0]
            let path = String(name[name.index(name.startIndex, offsetBy: prefix.count)..<dot])
            switch name[name.index(after: dot)...] {
            case "branch": branches[path] = String(parts[1])
            case "checkpoint": checkpoints[path] = String(parts[1])
            default: break
            }
        }
        var archived: [ArchivedWorktree] = []
        for (path, branch) in branches.sorted(by: { $0.key < $1.key }) {
            var checkpoint: Checkpoint?
            if let reference = checkpoints[path], let commit = try await resolve(reference) {
                checkpoint = Checkpoint(reference: reference, commit: commit)
            }
            archived.append(
                ArchivedWorktree(
                    path: URL(filePath: path, directoryHint: .isDirectory), branch: branch, checkpoint: checkpoint))
        }
        return archived
    }

    /// Forgets the record for `path`, if there is one: once its worktree is back, or when it's no
    /// longer wanted (its task was deleted).
    public func forgetArchivedWorktree(at path: URL) async throws(GitError) {
        // 128: there's no such record.
        try await run(
            ["config", "--remove-section", Self.archivedWorktreeSection(path)], acceptingStatus: [0, 128])
    }

    /// Brings back a recorded worktree: its branch (from the copy `archiveBranch` kept, if it was
    /// deleted), the folder checked out on it, and its uncommitted work; then forgets the record.
    /// Picks up where an interrupted archive or restore stopped: a worktree still (or already) at
    /// the path stays, and gets its checkpoint only when it has no changes of its own.
    @discardableResult
    public func restoreArchivedWorktree(_ archived: ArchivedWorktree) async throws(GitError) -> Worktree {
        if try await hasArchivedBranch(archived.branch) {
            try await restoreArchivedBranch(archived.branch)
        }
        let worktree: Worktree
        if let listed = await listedWorktree(at: archived.path, in: try await worktrees()) {
            worktree = listed
            if let checkpoint = archived.checkpoint, let repository = try await git.repository(at: listed.path),
                try await repository.changedFiles().changes.isEmpty
            {
                try await repository.restore(checkpoint)
            }
        } else {
            worktree = try await restoreWorktree(at: archived.path, branch: archived.branch, from: archived.checkpoint)
        }
        try await forgetArchivedWorktree(at: archived.path)
        return worktree
    }

    /// A folder path as the record's subsection: without the trailing slash a folder URL keeps.
    private static func archivedWorktreeSection(_ path: URL) -> String {
        var spelling = path.standardizedFileURL.path(percentEncoded: false)
        if spelling.count > 1, spelling.hasSuffix("/") { spelling.removeLast() }
        return "\(archivedWorktreeConfigSection).\(spelling)"
    }

    private static let archivedWorktreeConfigSection = "nativeArchivedWorktree"
}
