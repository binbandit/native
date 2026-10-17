import Foundation

extension PullRequest {
    public enum State: String, Sendable, Hashable, GitHubEnum {
        case open = "OPEN"
        case closed = "CLOSED"
        case merged = "MERGED"
        case other
    }

    /// The review requirement. A pull request without one (no branch protection) has `nil`.
    public enum ReviewDecision: String, Sendable, Hashable, GitHubEnum {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case reviewRequired = "REVIEW_REQUIRED"
        case other
    }

    /// Whether the head merges cleanly into the base. GitHub computes this lazily, so a fresh pull
    /// request reports `unknown` for a few seconds.
    public enum Mergeable: String, Sendable, Hashable, GitHubEnum {
        case mergeable = "MERGEABLE"
        case conflicting = "CONFLICTING"
        case unknown = "UNKNOWN"
        case other
    }

    /// GitHub's overall verdict on merging, protections and checks included
    /// (`mergeStateStatus`).
    public enum MergeStatus: String, Sendable, Hashable, GitHubEnum {
        /// The head is behind a base that must be up to date.
        case behind = "BEHIND"
        /// Protections block it: missing approvals, required checks.
        case blocked = "BLOCKED"
        case clean = "CLEAN"
        /// Conflicts.
        case dirty = "DIRTY"
        case draft = "DRAFT"
        case hasHooks = "HAS_HOOKS"
        case unknown = "UNKNOWN"
        /// Mergeable, but checks that aren't required failed.
        case unstable = "UNSTABLE"
        case other
    }
}
