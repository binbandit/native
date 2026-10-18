import Foundation

/// A comment in a review thread on a diff line.
public struct ReviewComment: Sendable, Hashable, Identifiable, Decodable {
    public enum State: String, Sendable, Hashable, GitHubEnum {
        /// In the viewer's pending review: only they see it until they submit.
        case pending = "PENDING"
        case submitted = "SUBMITTED"
        case other
    }

    public var id: String
    public var author: String?
    public var body: String
    public var createdAt: Date
    public var lastEditedAt: Date?
    public var url: URL?
    /// The diff around the comment when it was written, ending at its line.
    public var diffHunk: String
    public var state: State
    public var viewerCanUpdate: Bool
    public var viewerCanDelete: Bool

    public var isPending: Bool {
        state == .pending
    }

    public init(
        id: String, author: String?, body: String, createdAt: Date, lastEditedAt: Date? = nil,
        url: URL? = nil,
        diffHunk: String = "", state: State = .submitted, viewerCanUpdate: Bool = false,
        viewerCanDelete: Bool = false
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.lastEditedAt = lastEditedAt
        self.url = url
        self.diffHunk = diffHunk
        self.state = state
        self.viewerCanUpdate = viewerCanUpdate
        self.viewerCanDelete = viewerCanDelete
    }

    private enum CodingKeys: String, CodingKey {
        case id, author, body, createdAt, lastEditedAt, url, diffHunk, state, viewerCanUpdate,
            viewerCanDelete
    }

    private struct Login: Decodable {
        var login: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decodeIfPresent(Login.self, forKey: .author)?.login
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastEditedAt = try container.decodeIfPresent(Date.self, forKey: .lastEditedAt)
        url = try container.decodeText(forKey: .url).flatMap(URL.init(string:))
        diffHunk = try container.decodeIfPresent(String.self, forKey: .diffHunk) ?? ""
        state = try container.decodeEnum(State.self, forKey: .state) ?? .submitted
        viewerCanUpdate = try container.decodeIfPresent(Bool.self, forKey: .viewerCanUpdate) ?? false
        viewerCanDelete = try container.decodeIfPresent(Bool.self, forKey: .viewerCanDelete) ?? false
    }
}
