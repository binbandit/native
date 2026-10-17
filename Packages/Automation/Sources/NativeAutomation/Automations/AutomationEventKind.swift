import Foundation

/// Things that can start an automation. GitHub events come from polling (`AutomationEventDetector`),
/// never webhooks into the user's machine; the others come from Native itself.
public nonisolated enum AutomationEventKind: String, Codable, Hashable, Sendable, CaseIterable {
    case pullRequestOpened
    case pullRequestUpdated
    case reviewRequested
    case checksFailed
    /// A task the user started finished a turn.
    case taskFinished
    /// Native pushed a branch.
    case branchPushed

    public var label: String {
        switch self {
        case .pullRequestOpened: "A pull request is opened"
        case .pullRequestUpdated: "A pull request is updated"
        case .reviewRequested: "Your review is requested"
        case .checksFailed: "CI fails on a pull request"
        case .taskFinished: "A task finishes"
        case .branchPushed: "A branch is pushed"
        }
    }

    public var systemImage: String {
        switch self {
        case .pullRequestOpened, .pullRequestUpdated: "arrow.triangle.pull"
        case .reviewRequested: "eye"
        case .checksFailed: "xmark.octagon"
        case .taskFinished: "checkmark.circle"
        case .branchPushed: "arrow.up.circle"
        }
    }
}
