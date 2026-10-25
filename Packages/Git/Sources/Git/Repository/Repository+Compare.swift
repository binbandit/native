import Foundation

extension Repository {
    /// What to compare a branch against for `branch` (usually the default branch): the remote's
    /// copy when there is one, since a local `main` may be far behind.
    public func comparisonBase(for branch: String) async throws(GitError) -> String {
        let remotes = try await remotes()
        if let remote = remotes.contains("origin") ? "origin" : remotes.first,
            try await resolve("refs/remotes/\(remote)/\(branch)") != nil
        {
            return "\(remote)/\(branch)"
        }
        return branch
    }

    /// The branch's commits since it left `base`, newest first, subjects and bodies.
    public func commitLog(since base: String) async throws(GitError) -> String {
        try await run(["log", "--no-color", "--format=%h %s%n%n%b", "\(base)..HEAD"], readOnly: true).text
    }

    /// What the branch changed since it left `base` (`git diff base...HEAD`).
    public func branchDiff(since base: String) async throws(GitError) -> String {
        try await run(["diff", "--no-color", "--no-ext-diff", "--no-textconv", "\(base)...HEAD"], readOnly: true).text
    }

    /// The newest commit both `first` and `second` grow from (`git merge-base`), or nil when they
    /// share no history. Two worktrees of one repository share its commits, so this finds where two
    /// tasks started from the same point.
    public func mergeBase(_ first: String, _ second: String) async throws(GitError) -> String? {
        let output = try await run(["merge-base", first, second], readOnly: true, acceptingStatus: [0, 1])
        let commit = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.status == 0 && !commit.isEmpty ? commit : nil
    }
}
