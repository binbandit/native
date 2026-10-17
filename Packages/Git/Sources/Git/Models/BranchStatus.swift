import Foundation

/// The branch HEAD is on and how it compares with its upstream.
public struct BranchStatus: Hashable, Sendable {
    public enum Head: Hashable, Sendable {
        /// On a branch. With no `commit`, the branch is unborn: nothing has been committed yet.
        case branch(String)
        /// HEAD points straight at a commit.
        case detached
    }

    public var head: Head
    /// The commit HEAD points at; `nil` before the first commit.
    public var commit: String?
    /// The upstream's short name, e.g. "origin/main".
    public var upstream: String?
    /// Commits on the branch that aren't on its upstream.
    public var ahead: Int
    /// Commits on the upstream that aren't on the branch.
    public var behind: Int
    /// The branch tracks an upstream whose remote branch no longer exists.
    public var isUpstreamGone: Bool

    public init(
        head: Head, commit: String? = nil, upstream: String? = nil, ahead: Int = 0, behind: Int = 0,
        isUpstreamGone: Bool = false
    ) {
        self.head = head
        self.commit = commit
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.isUpstreamGone = isUpstreamGone
    }

    /// The branch's name, `nil` when detached.
    public var name: String? {
        if case .branch(let name) = head { name } else { nil }
    }

    public var isDetached: Bool { head == .detached }
    public var isUnborn: Bool { commit == nil }

    /// The branch name, or the abbreviated commit when detached.
    public var displayName: String {
        switch head {
        case .branch(let name): name
        case .detached: commit.map { String($0.prefix(7)) } ?? "HEAD"
        }
    }
}
