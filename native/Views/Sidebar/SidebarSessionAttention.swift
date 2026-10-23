import ACP
import Foundation

/// The exact request shown by a row, including its host-recorded arrival. Child asks keep their
/// own timestamps; opening or rebuilding a row never starts its clock again.
struct SidebarSessionAttention {
    let sentence: String
    let since: Date
    let answersShortcut: Bool

    init?(session: SessionModel, isVisibleTask: Bool) {
        if let question = session.pendingQuestion {
            sentence = question.request.message
            since = question.requestedAt
            answersShortcut = false
        } else if let call = session.permissionRequests.first, let permission = call.permission {
            sentence = call.askSummary
            since = permission.requestedAt
            answersShortcut = isVisibleTask && permission.options.contains { $0.kind == .allowOnce }
        } else if let child = session.children.values.compactMap({
            SidebarSessionAttention(session: $0, isVisibleTask: false)
        }).first {
            self = child
        } else {
            return nil
        }
    }
}
