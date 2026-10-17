import Foundation

/// A titled run of pull requests in the list.
public struct PullRequestGroup: Sendable, Hashable, Identifiable {
    public enum ID: Sendable, Hashable {
        case involvement(PullRequestSearch.Involvement)
        /// `owner/name`.
        case repository(String)
    }

    public var id: ID
    public var pullRequests: [PullRequestSummary]

    public init(_ id: ID, _ pullRequests: [PullRequestSummary]) {
        self.id = id
        self.pullRequests = pullRequests
    }

    /// The repository's `owner/name`, or the involvement's raw value; for sorting and keys.
    public var title: String {
        switch id {
        case .involvement(let involvement): involvement.rawValue
        case .repository(let repository): repository
        }
    }
}
