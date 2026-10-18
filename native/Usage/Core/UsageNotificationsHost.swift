import ACP
import Foundation

/// What notifications need from the app to decide whether to show and to act on the answer.
/// `AppModel` conforms.
protocol UsageNotificationsHost: AnyObject {
    /// Whether the task is the one on screen.
    func isShowing(_ ref: UsageSessionRef) -> Bool
    func lastTurnSummary(of ref: UsageSessionRef) -> TurnSummary?
    /// Whether the task's open question takes a single line of text.
    func canReplyInText(_ ref: UsageSessionRef) -> Bool
    /// Answers the task's oldest permission request, as ⌘Y or ⌘⇧⌫ would.
    func answerPermission(of ref: UsageSessionRef, allow: Bool) async
    /// Answers the task's open question; false when it couldn't take the text.
    func reply(to ref: UsageSessionRef, text: String) async -> Bool
    func show(_ ref: UsageSessionRef)
}
