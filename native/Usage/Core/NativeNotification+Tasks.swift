import ACP
import Foundation

// Notifications about tasks: long work finished, and the three ways a task waits on the user.
extension NativeNotification {
    /// "Done in 4m · 7 files changed", the turn's checkpoint summary.
    static func turnFinished(_ ref: UsageSessionRef, summary: TurnSummary) -> NativeNotification {
        var parts = summary.duration.map { ["Done in \(DSFormat.duration($0))"] } ?? ["Done"]
        let files = summary.changedFiles.count
        if files > 0 {
            parts.append(files == 1 ? "1 file changed" : "\(files) files changed")
        }
        var notification = NativeNotification(
            id: "native.task.\(ref.session.rawValue)", kind: .turnFinished, about: ref,
            title: ref.title ?? ref.agentName, body: parts.joined(separator: " · "))
        notification.subtitle = ref.agentName
        notification.sound = .done
        return notification
    }

    static func permission(_ ref: UsageSessionRef, toolCall: String) -> NativeNotification {
        var notification = NativeNotification(
            id: "native.task.\(ref.session.rawValue)", kind: .permission, about: ref,
            title: "\(ref.title ?? ref.agentName) needs approval", body: toolCall)
        notification.subtitle = ref.agentName
        notification.actions = [.allow, .reject]
        notification.sound = .needsYou
        return notification
    }

    /// `canReply` when the question takes a single line of text.
    static func question(_ ref: UsageSessionRef, message: String, canReply: Bool) -> NativeNotification {
        var notification = NativeNotification(
            id: "native.task.\(ref.session.rawValue)", kind: .question, about: ref,
            title: "\(ref.title ?? ref.agentName) has a question", body: message)
        notification.subtitle = ref.agentName
        notification.actions = canReply ? [.reply] : []
        notification.sound = .needsYou
        return notification
    }

    /// A workflow gate or blocked goal, or something that failed outside a turn. Without a task,
    /// it's Native's own.
    static func attention(_ kind: Kind, ref: UsageSessionRef?, reason: String) -> NativeNotification {
        let title = kind == .failed ? "Something stopped" : "Native needs you"
        guard let ref else {
            return NativeNotification(
                id: "native.attention.\(kind.rawValue)", kind: kind, agent: "", agentName: "Native",
                title: title, body: reason, sound: kind == .failed ? .none : .needsYou)
        }
        var notification = NativeNotification(
            id: "native.task.\(ref.session.rawValue)", kind: kind, about: ref, title: ref.title ?? ref.agentName,
            body: reason)
        notification.subtitle = ref.agentName
        notification.sound = kind == .failed ? .none : .needsYou
        return notification
    }
}
