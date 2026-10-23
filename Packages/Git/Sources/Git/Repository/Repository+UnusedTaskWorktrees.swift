import Foundation

extension Repository {
    /// Kept with the repository so a draft reopened after relaunch can release its old checkout.
    /// One value is atomic: an interrupted write cannot mix a branch with an older commit.
    public func recordUnusedTaskWorktree(_ worktree: Worktree) async throws(GitError) {
        guard let receipt = UnusedTaskWorktree(worktree: worktree),
            let data = try? JSONEncoder().encode(receipt), let json = String(data: data, encoding: .utf8)
        else { return }
        try await run(["config", "--local", Self.unusedWorktreeKey(receipt.path), json])
    }

    public func unusedTaskWorktree(at folder: URL) async throws(GitError) -> UnusedTaskWorktree? {
        guard let worktree = await listedWorktree(at: folder, in: try await worktrees()) else { return nil }
        let output = try await run(
            ["config", "--local", "--get", Self.unusedWorktreeKey(worktree.path)], readOnly: true,
            acceptingStatus: [0, 1])
        guard let receipt = try? JSONDecoder().decode(UnusedTaskWorktree.self, from: output.stdout),
            receipt.path.standardizedFileURL == worktree.path.standardizedFileURL
        else { return nil }
        return receipt
    }

    /// Removes an unused checkout only if it still matches its creation receipt. No force,
    /// checkpoint or branch deletion: a branch may have been chosen from existing work.
    /// Ignored files count as work too, including files produced by setup commands.
    @discardableResult
    public func removeUnusedTaskWorktree(_ receipt: UnusedTaskWorktree) async throws(GitError) -> Bool {
        guard let worktree = await listedWorktree(at: receipt.path, in: try await worktrees()),
            !worktree.isMain, !worktree.isLocked, !worktree.isPrunable,
            worktree.branch == receipt.branch, worktree.head == receipt.commit,
            let checkout = try await git.repository(at: worktree.path)
        else { return false }
        // Status can hide edits to assume-unchanged or skip-worktree entries. Such a checkout
        // cannot prove it is untouched, even when ordinary worktree removal would accept it.
        let entries = try await checkout.run(["ls-files", "-v", "-z"], readOnly: true)
        guard
            !entries.text.split(separator: "\0").contains(where: {
                $0.first.map { $0 == "S" || $0.isLowercase } ?? false
            })
        else { return false }
        let status = try await checkout.run(
            ["status", "--porcelain=v1", "--untracked-files=all", "--ignored", "--ignore-submodules=none"],
            readOnly: true)
        guard status.stdout.isEmpty else { return false }
        try await removeWorktree(at: worktree.path, checkpoint: false)
        _ = try? await run(["config", "--local", "--unset-all", Self.unusedWorktreeKey(receipt.path)])
        return true
    }

    private static func unusedWorktreeKey(_ folder: URL) -> String {
        "nativeUnusedTaskWorktree.\(folder.standardizedFileURL.path(percentEncoded: false)).receipt"
    }
}
