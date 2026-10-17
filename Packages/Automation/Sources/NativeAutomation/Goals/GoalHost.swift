import Foundation

/// What a goal needs from the session it drives. The app's adapter wraps a `SessionModel`; tests use
/// a double.
@MainActor
public protocol GoalHost: AnyObject {
    /// Whether a goal prompt can go out now: the agent is idle and nothing the user queued is
    /// waiting to go first. The user's own messages always take the next turn.
    var canSendGoalPrompt: Bool { get }
    /// The session's running cost, when its agent reports one.
    var goalSessionCost: Double? { get }
    /// What the agent said to close its latest turn.
    var goalLatestReply: String? { get }
    /// Sends `text` as the next prompt through the same path as the user's prompts, so the turn is
    /// reported back like any other. Returns once the turn is under way.
    func sendGoalPrompt(_ text: String) async
}
