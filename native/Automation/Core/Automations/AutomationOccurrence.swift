import Foundation

/// An event that happened, as automations match it: a pull request that changed, a task that
/// finished, a branch that was pushed.
nonisolated struct AutomationOccurrence: Codable, Hashable, Sendable {
    var kind: AutomationEventKind
    /// Unique per event, so one event never starts the same automation twice.
    var key: String
    /// `owner/name`, for GitHub events.
    var repository: String?
    /// The project folder, for events Native sees locally.
    var project: URL?
    /// What it's about, e.g. "acme/reports#214 Add CSV export".
    var subject: String
    var url: URL?
    var occurredAt: Date

    /// The line an automation's prompt gets, so the agent knows what to look at.
    var context: String {
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
