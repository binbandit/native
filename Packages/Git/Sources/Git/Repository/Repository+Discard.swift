import Foundation

extension Repository {
    /// Throws away changes after saving everything uncommitted as a checkpoint, so the discard can
    /// be taken back with `restore(_:paths:)`. Returns that checkpoint.
    ///
    /// - Untracked files are deleted.
    /// - Unstaged changes go back to what's staged.
    /// - Staged and conflicted changes go back to HEAD, in the index and the working tree.
    @discardableResult
    public func discard(_ changes: [FileChange]) async throws(GitError) -> Checkpoint? {
        guard !changes.isEmpty else { return nil }
        // An untracked folder is a nested repository: a checkpoint can't save what's inside it.
        if let nested = changes.first(where: { $0.path.hasSuffix("/") }) {
            throw .failed(
                arguments: ["clean"], status: 1,
                stderr:
                    "\(nested.path) is a separate repository; Native won't delete it. Remove it in Finder if you mean to."
            )
        }
        let checkpoint = try await checkpoint(named: "discard")
        let hasHead = try await resolve("HEAD") != nil
        var restoreFromIndex: [String] = []
        var restoreFromHead: [String] = []
        var removeFromIndex: [String] = []
        var delete: Set<String> = []

        for change in changes {
            switch change.area {
            case .untracked:
                delete.insert(change.path)
            case .unstaged:
                if change.kind != .deleted { delete.insert(change.path) }
                if change.kind == .added {
                    // An intent-to-add entry: drop it from the index too.
                    removeFromIndex.append(change.path)
                } else {
                    restoreFromIndex.append(change.path)
                }
            case .staged, .conflicted:
                delete.insert(change.path)
                let existedAtHead =
                    switch change.kind {
                    case .added, .copied: false
                    // Both sides may have added it.
                    case .conflicted: try await exists(change.path, at: "HEAD")
                    default: hasHead
                    }
                if change.kind == .renamed || change.kind == .copied || !existedAtHead {
                    removeFromIndex.append(change.path)
                } else {
                    restoreFromHead.append(change.path)
                }
                if let original = change.originalPath, change.kind == .renamed, hasHead {
                    restoreFromHead.append(original)
                }
            }
        }

        try await removeFiles(delete.sorted())
        if !removeFromIndex.isEmpty {
            try await runWithPaths(["rm", "--cached", "--quiet", "--force", "--ignore-unmatch", "-r"], removeFromIndex)
        }
        if !restoreFromHead.isEmpty {
            try await runWithPaths(["restore", "--source=HEAD", "--staged", "--worktree"], restoreFromHead)
        }
        if !restoreFromIndex.isEmpty {
            try await runWithPaths(["restore", "--worktree"], restoreFromIndex)
        }
        return checkpoint
    }

    func exists(_ path: String, at revision: String) async throws(GitError) -> Bool {
        try await run(["cat-file", "-e", "\(revision):\(path)"], readOnly: true, acceptingStatus: [0, 128]).status == 0
    }

    /// Deletes working tree files on the machine the repository is on.
    private func removeFiles(_ paths: [String]) async throws(GitError) {
        // Chunks keep the argument list well under the system's limit.
        for start in stride(from: 0, to: paths.count, by: 500) {
            let chunk = Array(paths[start..<min(start + 500, paths.count)])
            let output = try await git.runTool("rm", ["-f", "--"] + chunk, in: root)
            guard output.status == 0 else {
                throw .failed(arguments: ["rm"], status: output.status, stderr: output.stderr)
            }
        }
    }
}
