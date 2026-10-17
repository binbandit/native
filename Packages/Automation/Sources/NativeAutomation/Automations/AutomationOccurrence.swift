import Foundation

/// An event that happened, as automations match it: a pull request that changed, a task that
/// finished, a branch that was pushed.
public nonisolated struct AutomationOccurrence: Codable, Hashable, Sendable {
    public var kind: AutomationEventKind
    /// Unique per event, so one event never starts the same automation twice.
    public var key: String
    /// `owner/name`, for GitHub events.
    public var repository: String?
    /// The project folder, for events Native sees locally.
    public var project: URL?
    /// What it's about, e.g. "acme/reports#214 Add CSV export".
    public var subject: String
    public var url: URL?
    public var occurredAt: Date

    public init(kind: AutomationEventKind, key: String, repository: String? = nil, project: URL? = nil, subject: String, url: URL? = nil, occurredAt: Date) {
        self.kind = kind
        self.key = key
        self.repository = repository
        self.project = project
        self.subject = subject
        self.url = url
        self.occurredAt = occurredAt
    }

    /// The line an automation's prompt gets, so the agent knows what to look at.
    public var context: String {
        let what = switch kind {
        case .pullRequestOpened: "Pull request opened"
        case .pullRequestUpdated: "Pull request updated"
        case .reviewRequested: "Review requested"
        case .checksFailed: "CI failed"
        case .taskFinished: "Task finished"
        case .branchPushed: "Branch pushed"
        }
        return "\(what): \(subject)" + (url.map { " (\($0.absoluteString))" } ?? "")
    }
}
