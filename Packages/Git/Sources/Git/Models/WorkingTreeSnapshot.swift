import Foundation

/// A working tree as it was at one moment: HEAD, and a tree object holding every file git would
/// track there (untracked ones included, ignored ones not). Taken with `Repository.snapshot()`,
/// which touches no ref, index or file, so the tree is unreachable and git's garbage collection
/// may prune it after a couple of weeks (`Repository.hasObject(_:)` says whether it's still there).
public struct WorkingTreeSnapshot: Hashable, Sendable, Codable {
    /// HEAD's commit; nil before the first commit.
    public var head: String?
    /// The tree of the working tree's contents.
    public var tree: String

    public init(head: String?, tree: String) {
        self.head = head
        self.tree = tree
    }
}
