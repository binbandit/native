import Foundation

/// What carrying out a commit plan did, so it can be undone.
public struct CommitPlanReceipt: Hashable, Sendable {
    public var branch: String?
    /// HEAD before the first commit; `nil` before the repository's first commit.
    public var originalHead: String?
    /// The commits made, oldest first. Fewer than the plan's groups when one failed.
    public var commits: [String]
    /// Everything uncommitted beforehand, staged state included.
    public var checkpoint: Checkpoint?

    public init(branch: String?, originalHead: String?, commits: [String], checkpoint: Checkpoint?) {
        self.branch = branch
        self.originalHead = originalHead
        self.commits = commits
        self.checkpoint = checkpoint
    }
}
