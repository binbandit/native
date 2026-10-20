import Foundation

/// A task's workspace that was removed outside Native (a worktree deleted in Terminal or by another
/// tool) while its work isn't done: what the task shows, and the branch Restore Worktree checks out.
struct RemovedWorkspace: Hashable, Sendable {
    /// The branch to restore it on; nil when Native can't tell which it was.
    let branch: String?
    /// Why the task is kept: "binbandit/fix-login has 2 commits that aren't merged."
    let detail: String

    /// What should become of a task whose workspace was removed outside Native.
    enum Fate: Hashable, Sendable {
        /// Its work is done, so it's archived. `reason` ends "its worktree was removed, and …":
        /// "its branch is merged into main".
        case done(reason: String)
        /// Its work isn't done: it stays in sight, to restore or archive.
        case kept(RemovedWorkspace)
    }
}
