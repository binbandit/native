import Foundation

/// A pull request as `gh search prs --json` reports it. Search can't return branches, checks or
/// review state; `PullRequestStatus` fills those in.
public struct PullRequestSearchResult: Sendable, Hashable, Decodable, Identifiable {
    /// The GraphQL node id, which `pullRequestStatuses(ids:)` takes.
    public var id: String
    public var number: Int
    public var title: String
    public var url: URL
    public var state: PullRequest.State
    public var isDraft: Bool
    /// `owner/name`.
    public var repository: String
    public var author: GitHubActor?
    public var assignees: [GitHubActor]
    public var labels: [PullRequestLabel]
    public var commentsCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    static let fields = "id,number,title,url,state,isDraft,repository,author,assignees,labels,commentsCount,createdAt,updatedAt"

    private enum CodingKeys: String, CodingKey {
        case id, number, title, url, state, isDraft, repository, author, assignees, labels, commentsCount, createdAt, updatedAt
    }

    private struct RepositoryRef: Decodable {
        var nameWithOwner: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        state = try container.decodeEnum(PullRequest.State.self, forKey: .state) ?? .other
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        repository = try container.decode(RepositoryRef.self, forKey: .repository).nameWithOwner
        author = try container.decodeIfPresent(GitHubActor.self, forKey: .author)
        assignees = try container.decodeIfPresent([GitHubActor].self, forKey: .assignees) ?? []
        labels = try container.decodeIfPresent([PullRequestLabel].self, forKey: .labels) ?? []
        commentsCount = try container.decodeIfPresent(Int.self, forKey: .commentsCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
