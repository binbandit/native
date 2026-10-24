import ACP
import Foundation

/// A row and the global shortcut read the same request, even when it belongs to a child task.
struct SidebarSessionAttention {
    let sentence: String
    let since: Date
    let answersShortcut: Bool

    init?(session: SessionModel, task: SessionKey, oldest: TaskPeekAsk.ID?) {
        guard let ask = TaskPeekAsk.requests(in: session, task: task).first else { return nil }
        sentence = ask.sentence
        since = ask.since
        answersShortcut = ask.id == oldest
    }
}
