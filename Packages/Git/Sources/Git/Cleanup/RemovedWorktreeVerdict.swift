import Foundation

/// A task whose worktree folder is gone without Native having archived it (`git worktree remove`,
/// `rm -rf`, a prune, another tool): its folder and title, which tie it to the branch it was on.
public struct RemovedWorktreeTask: Hashable, Sendable {
    public var path: URL
    public var title: String?

    public init(path: URL, title: String?) {
        self.path = path
        self.title = title
    }
}

/// What a task whose worktree was removed outside Native should become
/// (`Repository.removedWorktreeVerdicts`).
public enum RemovedWorktreeVerdict: Hashable, Sendable {
    /// Its work is done: archive the task.
    case done(Done)
    /// Its branch has work the base doesn't: keep the task in sight, to restore its worktree or
    /// archive it.
    case unmerged(branch: String, why: MergedCleanupPlan.Kept.Why)
    /// More than one branch could be the one it was on, by name; Native doesn't guess, so the task
    /// stays in sight.
    case unknownBranch([String])

    public enum Done: Hashable, Sendable {
        /// Its branch's work is in the base, decided the way Clean Up Merged decides.
        case merged(branch: String, MergedCleanupPlan.Reason)
        /// Its branch never had commits of its own.
        case noCommits(branch: String)
        /// No branch of it is left: deleted, or only the copy Native keeps of a deleted one.
        case branchGone
    }
}
