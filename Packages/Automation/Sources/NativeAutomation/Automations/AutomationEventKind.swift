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

    /// The event as the end of "When …": "CI fails on a pull request".
    public var clause: String {
        switch self {
        case .pullRequestOpened: "a pull request is opened"
        case .pullRequestUpdated: "a pull request is updated"
        case .reviewRequested: "your review is requested"
        case .checksFailed: "CI fails on a pull request"
        case .taskFinished: "a task finishes"
        case .branchPushed: "a branch is pushed"
        }
    }

    /// The event on its own, for menus: "CI fails on a pull request".
    public var label: String {
        clause.prefix(1).uppercased() + clause.dropFirst()
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
