import Foundation

/// A pull request with what checking it out and briefing an agent on it take: where its head
/// lives (a fork or the base repository), whether maintainers may push there, its description and
/// its reviews. From `gh pr view --json`.
public struct PullRequestDetails: Sendable, Hashable, Decodable {
    public struct Review: Sendable, Hashable, Decodable {
        public var author: String?
        public var state: PullRequestReview.State?
        public var body: String
        public var submittedAt: Date?

        public init(author: String?, state: PullRequestReview.State?, body: String, submittedAt: Date? = nil) {
            self.author = author
            self.state = state
            self.body = body
            self.submittedAt = submittedAt
        }

        private enum CodingKeys: String, CodingKey {
            case author, state, body, submittedAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            author = try container.decodeIfPresent(GitHubActor.self, forKey: .author)?.login
            state = try container.decodeEnum(PullRequestReview.State.self, forKey: .state)
            body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
            submittedAt = try container.decodeIfPresent(Date.self, forKey: .submittedAt)?.ifSet
        }
    }

    public var number: Int
    public var title: String
    public var body: String
    public var url: URL
    public var state: PullRequest.State
    public var isDraft: Bool
    public var author: String?
    public var baseRefName: String
    public var headRefName: String
    /// The head commit when gh answered.
    public var headRefOid: String
    /// Where the head branch lives; `nil` when that repository was deleted, which leaves only
    /// GitHub's read-only copy of the head (`refs/pull/<n>/head`).
    public var headRepository: RemoteRepository?
    public var isCrossRepository: Bool
    /// The author lets the base repository's maintainers push to the head branch in their fork.
    public var maintainerCanModify: Bool
    public var reviews: [Review]

    public init(
        number: Int, title: String, body: String = "", url: URL, state: PullRequest.State = .open,
        isDraft: Bool = false, author: String? = nil, baseRefName: String, headRefName: String,
        headRefOid: String, headRepository: RemoteRepository?, isCrossRepository: Bool,
        maintainerCanModify: Bool = false, reviews: [Review] = []
    ) {
        self.number = number
        self.title = title
        self.body = body
        self.url = url
        self.state = state
        self.isDraft = isDraft
        self.author = author
        self.baseRefName = baseRefName
        self.headRefName = headRefName
        self.headRefOid = headRefOid
        self.headRepository = headRepository
        self.isCrossRepository = isCrossRepository
        self.maintainerCanModify = maintainerCanModify
        self.reviews = reviews
    }

    /// The repository it asks to merge into, from its URL.
    public var baseRepository: RemoteRepository? {
        PullRequestReference(url: url).map { RemoteRepository(host: $0.host, owner: $0.owner, name: $0.name) }
    }

    public var reference: PullRequestReference? {
        PullRequestReference(url: url)
    }

    static let fields = [
        "number", "title", "body", "url", "state", "isDraft", "author", "baseRefName", "headRefName",
        "headRefOid", "headRepository", "headRepositoryOwner", "isCrossRepository", "maintainerCanModify",
        "reviews",
    ].joined(separator: ",")

    private enum CodingKeys: String, CodingKey {
        case number, title, body, url, state, isDraft, author, baseRefName, headRefName, headRefOid,
            headRepository, headRepositoryOwner, isCrossRepository, maintainerCanModify, reviews
    }

    private struct Repository: Decodable {
        var name: String?
        var nameWithOwner: String?
    }

    private struct Owner: Decodable {
        var login: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        url = try container.decode(URL.self, forKey: .url)
        state = try container.decodeEnum(PullRequest.State.self, forKey: .state) ?? .other
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        author = try container.decodeIfPresent(GitHubActor.self, forKey: .author)?.login
        baseRefName = try container.decodeIfPresent(String.self, forKey: .baseRefName) ?? ""
        headRefName = try container.decodeIfPresent(String.self, forKey: .headRefName) ?? ""
        headRefOid = try container.decodeIfPresent(String.self, forKey: .headRefOid) ?? ""
        isCrossRepository = try container.decodeIfPresent(Bool.self, forKey: .isCrossRepository) ?? false
        maintainerCanModify = try container.decodeIfPresent(Bool.self, forKey: .maintainerCanModify) ?? false
        reviews = try container.decodeIfPresent([Review].self, forKey: .reviews) ?? []

        // gh prints a deleted fork as an empty object (or null), and older versions leave out
        // `nameWithOwner`, which the owner's login and the name make up.
        let host = url.host() ?? "github.com"
        let repository = try container.decodeIfPresent(Repository.self, forKey: .headRepository)
        let owner = try container.decodeIfPresent(Owner.self, forKey: .headRepositoryOwner)?.login
        if let nameWithOwner = repository?.nameWithOwner, !nameWithOwner.isEmpty {
            headRepository = RemoteRepository(nameWithOwner: nameWithOwner, host: host)
        } else if let name = repository?.name, !name.isEmpty, let owner, !owner.isEmpty {
            headRepository = RemoteRepository(host: host, owner: owner, name: name)
        } else {
            headRepository = nil
        }
    }
}
