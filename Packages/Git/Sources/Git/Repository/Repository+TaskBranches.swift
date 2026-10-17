import Foundation

extension Repository {
    /// `base`, or `base-2`, `base-3`… when a local or remote branch already has the name.
    public func uniqueBranchName(_ base: String) async throws(GitError) -> String {
        let taken = try await takenBranchNames()
        for attempt in 1...100 {
            let name = attempt == 1 ? base : "\(base)-\(attempt)"
            if !taken.contains(name) { return name }
        }
        throw .failed(arguments: ["branch"], status: 1, stderr: "Every branch name for “\(base)” is taken.")
    }

    /// Creates `name` at HEAD and switches this working tree to it, carrying uncommitted changes
    /// along, for tasks that work on a branch in the main checkout instead of a worktree.
    public func createAndSwitchBranch(_ name: String) async throws(GitError) {
        try await run(["switch", "--create", name])
    }

    /// Marks a branch as named provisionally, so `renameProvisionalBranch` may rename it. The mark
    /// lives in the repository's config, which travels with `git branch -m`.
    public func markProvisional(_ branch: String) async throws(GitError) {
        try await run(["config", "branch.\(branch).nativeProvisional", "true"])
    }

    public func isProvisional(_ branch: String) async throws(GitError) -> Bool {
        let output = try await run(
            ["config", "--get", "--bool", "branch.\(branch).nativeProvisional"], readOnly: true,
            acceptingStatus: [0, 1])
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Whether the branch has been pushed: it tracks an upstream, or a remote has its name.
    public func isPublished(_ branch: String) async throws(GitError) -> Bool {
        let upstream = try await run(
            ["config", "--get", "branch.\(branch).merge"], readOnly: true, acceptingStatus: [0, 1])
        if upstream.status == 0 { return true }
        let remote = try await run(
            ["for-each-ref", "--format=%(refname)", "refs/remotes/*/\(branch)"], readOnly: true)
        return !remote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Renames a provisionally named branch after the task's title (`<prefix><title-in-kebab-case>`,
    /// made unique), unless it was renamed or pushed since. Returns the new name, or `nil` when it
    /// was left alone.
    @discardableResult
    public func renameProvisionalBranch(_ branch: String, title: String) async throws(GitError) -> String? {
        guard try await isProvisional(branch), try await !isPublished(branch) else { return nil }
        let base = BranchNaming.name(forTitle: title, prefix: BranchNaming.prefix(ofProvisional: branch))
        guard base != branch else { return nil }
        let name = try await uniqueBranchName(base)
        try await run(["branch", "--move", branch, name])
        try await run(["config", "--unset", "branch.\(name).nativeProvisional"], acceptingStatus: [0, 5])
        return name
    }

    /// Deletes a branch, keeping its tip under `refs/native-archived-branches/` so its commits stay
    /// reachable and `restoreArchivedBranch` can bring it back. Returns that ref.
    @discardableResult
    public func archiveBranch(_ branch: String) async throws(GitError) -> String {
        guard let tip = try await resolve("refs/heads/\(branch)") else {
            throw .failed(arguments: ["branch", "-D"], status: 1, stderr: "There's no branch named “\(branch)”.")
        }
        let reference = "refs/native-archived-branches/\(branch)"
        try await run(["update-ref", reference, tip])
        try await run(["branch", "--delete", "--force", branch])
        return reference
    }

    /// Recreates a branch `archiveBranch` deleted, at the commit it had.
    public func restoreArchivedBranch(_ branch: String) async throws(GitError) {
        let reference = "refs/native-archived-branches/\(branch)"
        try await run(["branch", branch, reference])
        try await run(["update-ref", "-d", reference])
    }
}
