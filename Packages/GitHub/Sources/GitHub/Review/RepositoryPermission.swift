import Foundation

/// The viewer's role in a repository, which decides what they can do to its pull requests.
public enum RepositoryPermission: String, Sendable, Hashable, Comparable, GitHubEnum {
    case read = "READ"
    case triage = "TRIAGE"
    case write = "WRITE"
    case maintain = "MAINTAIN"
    case admin = "ADMIN"
    case other

    /// Merging needs push access.
    public var canMerge: Bool {
        self >= .write && self != .other
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .other: 0
        case .read: 1
        case .triage: 2
        case .write: 3
        case .maintain: 4
        case .admin: 5
        }
    }
}
