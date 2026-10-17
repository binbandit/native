import Foundation

/// One entry of a pull request's `statusCheckRollup`: a check run (GitHub Actions and other apps)
/// or a commit status (older integrations: CI services, deploy previews).
public struct StatusCheck: Sendable, Hashable, Decodable {
    public enum Kind: String, Sendable, Hashable, GitHubEnum {
        case checkRun = "CheckRun"
        case statusContext = "StatusContext"
        case other
    }

    public var kind: Kind
    /// The check run's name, or the commit status's context.
    public var name: String
    /// The Actions workflow that ran it.
    public var workflow: String?
    /// A check run's QUEUED / IN_PROGRESS / COMPLETED, or a commit status's state.
    public var status: String?
    /// SUCCESS, FAILURE, ... once a check run has completed.
    public var conclusion: String?
    public var detailsURL: URL?
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        kind: Kind, name: String, workflow: String? = nil, status: String?, conclusion: String? = nil,
        detailsURL: URL? = nil, startedAt: Date? = nil, completedAt: Date? = nil
    ) {
        self.kind = kind
        self.name = name
        self.workflow = workflow
        self.status = status
        self.conclusion = conclusion
        self.detailsURL = detailsURL
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var outcome: CheckOutcome {
        if kind == .statusContext {
            return CheckOutcome(state: status ?? "")
        }
        // A run is judged by its conclusion only once it completes; until then it's pending.
        if status?.uppercased() == "COMPLETED", let conclusion {
            return CheckOutcome(state: conclusion)
        }
        return .pending
    }

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case name, context, workflowName, status, state, conclusion, detailsUrl, targetUrl, startedAt, completedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeEnum(Kind.self, forKey: .typename) ?? .other
        if kind == .statusContext {
            name = try container.decodeIfPresent(String.self, forKey: .context) ?? ""
            status = try container.decodeText(forKey: .state)
            conclusion = nil
        } else {
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            status = try container.decodeText(forKey: .status)
            conclusion = try container.decodeText(forKey: .conclusion)
        }
        workflow = try container.decodeText(forKey: .workflowName)
        let link = try container.decodeText(forKey: .detailsUrl) ?? container.decodeText(forKey: .targetUrl)
        detailsURL = link.flatMap(URL.init(string:))
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)?.ifSet
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)?.ifSet
    }
}
