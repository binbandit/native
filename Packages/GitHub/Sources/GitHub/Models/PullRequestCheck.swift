import Foundation

/// A check as `gh pr checks --json` lists it, with gh's own bucketing.
public struct PullRequestCheck: Sendable, Hashable, Decodable {
    public enum Bucket: String, Sendable, Hashable, GitHubEnum {
        case pass, fail, pending, skipping, cancel
        case other
    }

    public var name: String
    /// The raw state: SUCCESS, FAILURE, IN_PROGRESS, NEUTRAL, ...
    public var state: String
    public var bucket: Bucket?
    public var link: URL?
    public var workflow: String?
    public var description: String?
    /// What triggered the workflow, e.g. `pull_request`.
    public var event: String?
    public var startedAt: Date?
    public var completedAt: Date?

    public init(name: String, state: String, bucket: Bucket?, link: URL? = nil, workflow: String? = nil, description: String? = nil, event: String? = nil, startedAt: Date? = nil, completedAt: Date? = nil) {
        self.name = name
        self.state = state
        self.bucket = bucket
        self.link = link
        self.workflow = workflow
        self.description = description
        self.event = event
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var outcome: CheckOutcome {
        switch bucket {
        case .pass: .passed
        case .fail, .cancel: .failed
        case .skipping: .skipped
        case .pending: .pending
        case .other, nil: CheckOutcome(state: state)
        }
    }

    static let fields = "name,state,bucket,link,workflow,description,event,startedAt,completedAt"

    private enum CodingKeys: String, CodingKey {
        case name, state, bucket, link, workflow, description, event, startedAt, completedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        bucket = try container.decodeEnum(Bucket.self, forKey: .bucket)
        link = try container.decodeText(forKey: .link).flatMap(URL.init(string:))
        workflow = try container.decodeText(forKey: .workflow)
        description = try container.decodeText(forKey: .description)
        event = try container.decodeText(forKey: .event)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)?.ifSet
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)?.ifSet
    }
}
