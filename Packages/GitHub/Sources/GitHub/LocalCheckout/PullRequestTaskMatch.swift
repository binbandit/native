import Foundation

/// Finding the task already working on a pull request, so opening it again goes there instead of
/// making a second checkout, and telling whether that task is behind the pull request.
public enum PullRequestTaskMatch {
    /// A task in the project, with the pull request its checkout was made for, if any.
    public struct Candidate<ID: Hashable & Sendable>: Sendable, Hashable {
        public var id: ID
        /// The pull request link stored with the task's checkout.
        public var link: URL?
        public var isArchived: Bool
        public var updatedAt: Date?

        public init(id: ID, link: URL?, isArchived: Bool = false, updatedAt: Date? = nil) {
            self.id = id
            self.link = link
            self.isArchived = isArchived
            self.updatedAt = updatedAt
        }
    }

    /// The task for `pullRequest`: one in the sidebar over an archived one, then the most recently
    /// active. Links match however they're spelled (`/files`, a different case).
    public static func existing<ID>(
        for pullRequest: PullRequestReference, among candidates: [Candidate<ID>]
    ) -> Candidate<ID>? {
        candidates
            .filter { candidate in
                candidate.link.flatMap(PullRequestReference.init(url:))?.isSamePullRequest(as: pullRequest) == true
            }
            .min { lhs, rhs in
                if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
                return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            }
    }

    /// Where a task's checkout stands against the pull request on GitHub.
    public enum HeadState: Sendable, Hashable {
        /// The checkout has the pull request's head commit (and maybe commits of its own).
        case current
        /// The pull request has commits the checkout doesn't: pushed since, or rewritten.
        case moved
    }

    /// - Parameters:
    ///   - hasHeadCommit: Whether the repository has the pull request's head commit at all.
    ///   - containsHeadCommit: Whether the checkout's HEAD has it in its history.
    public static func headState(hasHeadCommit: Bool, containsHeadCommit: Bool) -> HeadState {
        hasHeadCommit && containsHeadCommit ? .current : .moved
    }
}

extension PullRequestReference {
    /// The same pull request, comparing owner and name the way GitHub does, without case.
    public func isSamePullRequest(as other: PullRequestReference) -> Bool {
        number == other.number && host.caseInsensitiveCompare(other.host) == .orderedSame
            && owner.caseInsensitiveCompare(other.owner) == .orderedSame
            && name.caseInsensitiveCompare(other.name) == .orderedSame
    }
}
