import Foundation

/// A branch in a local checkout: what a task's pull request badge looks up.
struct BranchReference: Hashable, Sendable {
    /// The checkout (usually the task's worktree), which tells gh the repository.
    var directory: URL
    var branch: String
}
