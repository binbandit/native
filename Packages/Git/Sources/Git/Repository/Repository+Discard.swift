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
        let checkpoint = try await checkpoint(named: "discard")
        let hasHead = try await run(["rev-parse", "--verify", "--quiet", "HEAD"], readOnly: true, acceptingStatus: [0, 1]).status == 0
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
                let existedAtHead = switch change.kind {
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

        for path in delete.sorted() {
            try removeFile(path)
        }
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

    private func removeFile(_ path: String) throws(GitError) {
        let url = root.appending(path: path, directoryHint: .notDirectory)
        let fileManager = FileManager.default
        // A dangling symlink isn't "reachable" but still has to go.
        guard (try? url.checkResourceIsReachable()) == true || (try? fileManager.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))) != nil else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw .launchFailed("Couldn't remove \(path): \(error.localizedDescription)")
        }
    }
}
