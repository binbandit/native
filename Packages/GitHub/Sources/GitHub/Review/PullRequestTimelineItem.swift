import Foundation

/// One entry of a pull request's conversation: a comment, a review, a pushed commit or an event
/// such as a label or a merge. Kinds this version doesn't show decode as `.other`.
public enum PullRequestTimelineItem: Sendable, Hashable, Identifiable, Decodable {
    case comment(Comment)
    case review(Review)
    case commit(Commit)
    case event(Event)
    case other(id: String)

    public var id: String {
        switch self {
        case .comment(let comment): comment.id
        case .review(let review): review.id
        case .commit(let commit): commit.id
        case .event(let event): event.id
        case .other(let id): id
        }
    }

    public var date: Date? {
        switch self {
        case .comment(let comment): comment.createdAt
        case .review(let review): review.submittedAt
        case .commit(let commit): commit.date
        case .event(let event): event.date
        case .other: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .typename) ?? ""
        switch type {
        case "IssueComment":
            self = .comment(try Comment(from: decoder))
        case "PullRequestReview":
            self = .review(try Review(from: decoder))
        case "PullRequestCommit":
            self = .commit(try Commit(from: decoder))
        default:
            if let event = try Event(type: type, decoder: decoder) {
                self = .event(event)
            } else {
                self = .other(
                    id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString)
            }
        }
    }
}
