import Foundation

/// The checked-out branch's own commits as one mailbox (`git format-patch`), which `git am`
/// applies on another machine with each commit's message and author.
public struct BranchPatch: Equatable, Sendable {
    /// Empty when there are no commits to export, or when merges make the export unfaithful.
    public let data: Data
    public let commits: Int
    /// Merge commits on the branch. A mailbox can't carry them (`format-patch` skips merges and
    /// whatever they changed), so a branch with any gets no patch rather than an incomplete one.
    public let merges: Int
    /// What the commits were taken against, such as `origin/main`.
    public let base: String
}

extension Repository {
    /// The branch's commits since `branchBase()`, binary files included. Nil when there's nothing to
    /// compare the branch with. Uncommitted changes are never part of it.
    public func branchPatch() async throws(GitError) -> BranchPatch? {
        guard let base = try await branchBase() else { return nil }
        let range = "\(base.commit)..HEAD"
        let commits = try await count(["--no-merges", range])
        let merges = try await count(["--merges", range])
        guard commits > 0, merges == 0 else {
            return BranchPatch(data: Data(), commits: commits, merges: merges, base: base.name)
        }
        let output = try await run(
            ["format-patch", "--stdout", "--binary", "--no-color", "--no-signature", range], readOnly: true)
        return BranchPatch(data: output.stdout, commits: commits, merges: 0, base: base.name)
    }

    private func count(_ revisions: [String]) async throws(GitError) -> Int {
        let output = try await run(["rev-list", "--count"] + revisions, readOnly: true).text
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}
