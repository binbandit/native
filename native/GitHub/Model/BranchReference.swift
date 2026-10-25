import Foundation

/// A branch in a checkout on this Mac or on a paired host: what a task's pull request badge looks
/// up. The same folder and branch on two machines are two references, each answered by gh there.
struct BranchReference: Hashable, Sendable {
    /// The paired host the checkout is on; `nil` for this Mac.
    var host: RemoteHostID? = nil
    /// The checkout (usually the task's worktree), spelled as its machine spells it, which tells gh
    /// the repository.
    var directory: URL
    var branch: String
}
