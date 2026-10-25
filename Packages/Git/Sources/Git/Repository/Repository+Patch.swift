import Foundation

/// The checked-out branch's own commits as one mailbox (`git format-patch`), which `git am`
/// applies on another machine with each commit's message and author.
public struct BranchPatch: Equatable, Sendable {
    public let data: Data
    public let commits: Int
    /// What the commits were taken against, such as `origin/main`.
    public let base: String
}

extension Repository {
    /// The branch's commits since `branchBase()`, binary files included. Nil when there's nothing to
    /// compare the branch with; a branch with no commits of its own yet gives an empty patch.
    /// Uncommitted changes are never part of it.
    public func branchPatch() async throws(GitError) -> BranchPatch? {
        guard let base = try await branchBase() else { return nil }
        let range = "\(base.commit)..HEAD"
        let counted = try await run(["rev-list", "--count", range], readOnly: true).text
        let commits = Int(counted.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard commits > 0 else { return BranchPatch(data: Data(), commits: 0, base: base.name) }
        let output = try await run(
            ["format-patch", "--stdout", "--binary", "--no-color", "--no-signature", range], readOnly: true)
        return BranchPatch(data: output.stdout, commits: commits, base: base.name)
    }
}
