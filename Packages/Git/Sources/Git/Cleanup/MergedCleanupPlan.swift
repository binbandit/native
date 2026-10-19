import Foundation

/// What cleaning up a repository's merged work would do: Native's task worktrees and the local
/// branches whose work is already in the base branch, worktree records whose folders are gone, and
/// leftover task folders, each with why it qualifies. Built by `Repository.mergedCleanupPlan`;
/// nothing is changed until the caller acts on it.
public struct MergedCleanupPlan: Sendable, Hashable {
    /// Why a branch's work counts as merged.
    public enum Reason: Sendable, Hashable {
        /// A merged pull request has the branch's commits, however it was merged (squash, rebase,
        /// merge commit). `base` is the branch it was merged into.
        case pullRequest(number: Int, url: URL?, base: String)
        /// The branch's commits are in the base branch's history.
        case ancestry(base: String)
        /// Merging the branch into the base branch would change nothing: its changes landed another
        /// way (a squash or rebase merge), found by comparing content.
        case sameContent(base: String)
    }

    /// A worktree Native made for a task, whose branch (or detached commit) is merged.
    public struct TaskWorktree: Sendable, Hashable, Identifiable {
        public var path: URL
        /// `nil` when its HEAD is detached.
        public var branch: String?
        public var reason: Reason
        /// Files with uncommitted changes, which removing the worktree saves as a checkpoint;
        /// `nil` when git couldn't say.
        public var uncommittedFiles: Int?
        /// The folder's size on disk, when it could be measured.
        public var bytes: Int?

        public var id: URL { path }
    }

    /// A local branch whose work is merged, which can be deleted.
    public struct MergedBranch: Sendable, Hashable, Identifiable {
        public var name: String
        /// The commit it points at, which deleting it keeps (see `Repository.archiveBranch`).
        public var tip: String
        public var reason: Reason
        /// Native made it: named with Native's prefix, marked by Native, or checked out in a task
        /// worktree. Other merged branches are offered too, off by default.
        public var isNative: Bool
        /// The task worktree (or stale worktree record) it's checked out in, which has to go before
        /// the branch can be deleted.
        public var checkedOutIn: URL?

        public var id: String { name }
    }

    /// A worktree git still lists whose folder is gone (`git worktree prune` would forget it).
    public struct StaleRecord: Sendable, Hashable, Identifiable {
        public var path: URL
        public var branch: String?

        public var id: URL { path }
    }

    /// A folder in Native's task worktree location left behind by a worktree of this repository
    /// that git no longer knows about.
    public struct LeftoverFolder: Sendable, Hashable, Identifiable {
        public var path: URL
        public var bytes: Int?

        public var id: URL { path }
    }

    /// One of Native's branches or worktrees that stays, and why, so a task the user expected to
    /// see cleaned up isn't a mystery.
    public struct Kept: Sendable, Hashable, Identifiable {
        public enum Why: Sendable, Hashable {
            /// Commits on it aren't in the base branch.
            case unmergedCommits(Int)
            /// A pull request for it was merged, but it has commits since that the pull request
            /// doesn't.
            case changedSincePullRequest(number: Int)
            /// It never had commits of its own: its task hasn't committed anything yet.
            case noCommits
            /// The base branch, the main checkout's branch, or a protected name (main, release/*).
            case protected
            /// Checked out in a worktree that isn't one of Native's.
            case checkedOutElsewhere(URL)
            /// Its worktree is locked (`git worktree lock`).
            case locked
        }

        public var branch: String?
        /// The task worktree, when the kept thing is one.
        public var worktree: URL?
        public var why: Why

        public var id: String { worktree?.path(percentEncoded: false) ?? branch ?? "" }
    }

    /// How GitHub was consulted about pull requests.
    public enum PullRequestCheck: Sendable, Hashable {
        /// Merged pull requests were looked up for the branches that have been pushed.
        case checked
        /// GitHub couldn't be asked (gh missing, signed out, offline, not a GitHub repository), so
        /// squash and rebase merges were found by comparing content instead. Says why.
        case unavailable(String)
        /// No branch needed it: nothing had been pushed.
        case notNeeded
    }

    /// The branch work has to be in, such as "main".
    public var base: String
    public var worktrees: [TaskWorktree]
    public var branches: [MergedBranch]
    public var staleRecords: [StaleRecord]
    public var leftoverFolders: [LeftoverFolder]
    public var kept: [Kept]
    public var pullRequestCheck: PullRequestCheck

    public init(
        base: String, worktrees: [TaskWorktree] = [], branches: [MergedBranch] = [], staleRecords: [StaleRecord] = [],
        leftoverFolders: [LeftoverFolder] = [], kept: [Kept] = [], pullRequestCheck: PullRequestCheck = .notNeeded
    ) {
        self.base = base
        self.worktrees = worktrees
        self.branches = branches
        self.staleRecords = staleRecords
        self.leftoverFolders = leftoverFolders
        self.kept = kept
        self.pullRequestCheck = pullRequestCheck
    }

    public var isEmpty: Bool {
        worktrees.isEmpty && branches.isEmpty && staleRecords.isEmpty && leftoverFolders.isEmpty
    }
}
