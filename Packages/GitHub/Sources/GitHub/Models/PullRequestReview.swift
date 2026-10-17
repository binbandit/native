import Foundation

public struct PullRequestReview: Sendable, Hashable, Decodable {
    public enum State: String, Sendable, Hashable, GitHubEnum {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case commented = "COMMENTED"
        case dismissed = "DISMISSED"
        case pending = "PENDING"
        case other
    }

    public var author: GitHubActor?
    public var state: State?
    public var submittedAt: Date?

    public init(author: GitHubActor?, state: State?, submittedAt: Date? = nil) {
        self.author = author
        self.state = state
        self.submittedAt = submittedAt
    }

    private enum CodingKeys: String, CodingKey {
        case author, state, submittedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decodeIfPresent(GitHubActor.self, forKey: .author)
        state = try container.decodeEnum(State.self, forKey: .state)
        submittedAt = try container.decodeIfPresent(Date.self, forKey: .submittedAt)?.ifSet
    }
}
