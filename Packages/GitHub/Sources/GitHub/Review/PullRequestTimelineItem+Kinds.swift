import Foundation

extension PullRequestTimelineItem {
    /// A comment on the conversation (an issue comment), or the pull request's description.
    public struct Comment: Sendable, Hashable, Identifiable, Decodable {
        public var id: String
        public var author: String?
        public var body: String
        public var createdAt: Date
        public var lastEditedAt: Date?
        public var url: URL?
        public var viewerCanUpdate: Bool
        public var viewerCanDelete: Bool

        public init(
            id: String, author: String?, body: String, createdAt: Date, lastEditedAt: Date? = nil,
            url: URL? = nil,
            viewerCanUpdate: Bool = false, viewerCanDelete: Bool = false
        ) {
            self.id = id
            self.author = author
            self.body = body
            self.createdAt = createdAt
            self.lastEditedAt = lastEditedAt
            self.url = url
            self.viewerCanUpdate = viewerCanUpdate
            self.viewerCanDelete = viewerCanDelete
        }

        private enum CodingKeys: String, CodingKey {
            case id, author, body, createdAt, lastEditedAt, url, viewerCanUpdate, viewerCanDelete
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            author = try container.decodeIfPresent(TimelineLogin.self, forKey: .author)?.login
            body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            lastEditedAt = try container.decodeIfPresent(Date.self, forKey: .lastEditedAt)
            url = try container.decodeText(forKey: .url).flatMap(URL.init(string:))
            viewerCanUpdate = try container.decodeIfPresent(Bool.self, forKey: .viewerCanUpdate) ?? false
            viewerCanDelete = try container.decodeIfPresent(Bool.self, forKey: .viewerCanDelete) ?? false
        }
    }

    /// A submitted review: its verdict, its summary, and how many line comments came with it.
    public struct Review: Sendable, Hashable, Identifiable, Decodable {
        public var id: String
        public var author: String?
        public var state: PullRequestReview.State
        public var body: String
        public var submittedAt: Date?
        public var url: URL?
        public var commentCount: Int

        private enum CodingKeys: String, CodingKey {
            case id, author, state, body, submittedAt, createdAt, url, comments
        }

        private struct Count: Decodable {
            var totalCount: Int
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            author = try container.decodeIfPresent(TimelineLogin.self, forKey: .author)?.login
            state = try container.decodeEnum(PullRequestReview.State.self, forKey: .state) ?? .other
            body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
            submittedAt =
                try container.decodeIfPresent(Date.self, forKey: .submittedAt)
                ?? container.decodeIfPresent(Date.self, forKey: .createdAt)
            url = try container.decodeText(forKey: .url).flatMap(URL.init(string:))
            commentCount = try container.decodeIfPresent(Count.self, forKey: .comments)?.totalCount ?? 0
        }
    }

    /// A commit pushed to the branch.
    public struct Commit: Sendable, Hashable, Identifiable, Decodable {
        public var id: String
        public var oid: String
        public var abbreviatedOid: String
        public var headline: String
        public var date: Date?
        public var author: String?

        private enum CodingKeys: String, CodingKey {
            case id, commit
        }

        private struct Payload: Decodable {
            struct Author: Decodable {
                var name: String?
                var user: TimelineLogin?
            }

            var oid: String
            var abbreviatedOid: String?
            var messageHeadline: String?
            var committedDate: Date?
            var author: Author?
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            let commit = try container.decode(Payload.self, forKey: .commit)
            oid = commit.oid
            abbreviatedOid = commit.abbreviatedOid ?? String(commit.oid.prefix(7))
            headline = commit.messageHeadline ?? ""
            date = commit.committedDate
            author = commit.author?.user?.login ?? commit.author?.name
        }
    }
}

/// `{ "login": … }`, as GraphQL nests actors.
struct TimelineLogin: Decodable, Hashable, Sendable {
    var login: String
}
