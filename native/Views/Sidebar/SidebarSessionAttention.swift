import ACP
import Foundation

/// A row and the global shortcut read the same request, even when it belongs to a child task.
struct SidebarSessionAttention {
    let id: TaskPeekAsk.ID
    let sentence: String
    let since: Date
    let answersShortcut: Bool
    let pushRequest: ApprovalPushReach.Request?

    init?(
        session: SessionModel, task: SessionKey, oldest: TaskPeekAsk.ID?, pushPlace: String? = nil,
        pushBranch: String? = nil
    ) {
        guard let ask = TaskPeekAsk.requests(in: session, task: task).first else { return nil }
        id = ask.id
        sentence = ask.sentence(pushPlace: pushPlace, pushBranch: pushBranch)
        pushRequest = ask.pushRequest
        since = ask.since
        answersShortcut = ask.id == oldest
    }
}
