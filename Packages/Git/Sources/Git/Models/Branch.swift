import Foundation

/// A local or remote-tracking branch.
public struct Branch: Hashable, Sendable, Identifiable {
    /// The short name: "main", or "origin/main" for a remote-tracking branch.
    public var name: String
    /// The full ref, e.g. "refs/heads/main".
    public var reference: String
    public var isRemote: Bool
    /// HEAD is on this branch in this working tree.
    public var isCurrent: Bool
    public var commit: String
    /// The upstream's short name, for local branches that track one.
    public var upstream: String?
    /// The working tree that has this branch checked out, if any.
    public var worktreePath: URL?
    public var committerDate: Date?

    public var id: String { reference }
}
