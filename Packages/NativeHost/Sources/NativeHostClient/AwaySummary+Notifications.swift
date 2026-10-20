import Foundation
import NativeHostProtocol

// "While you were away" from the host's notifications (docs/durability.md, "Notifications"), for
// clients that follow them: the same summary the activity journal gives, from the events every
// client and the phone are told about.
extension AwaySummary {
    /// Folds a host's notifications (oldest first) into one item per task. Only those still news
    /// count: an approval answered on another device, or a finished task seen there, isn't news
    /// here. Nil when nothing is.
    public init?(notifications: [HostNotification]) {
        var items: [HostSessionID: Item] = [:]
        var recoveries: [RecoveryNote] = []
        var since: Date?
        for notification in notifications where notification.state == .active {
            guard let outcome = Self.outcome(of: notification) else { continue }
            var item =
                items[notification.taskID]
                ?? Item(
                    id: notification.taskID, agentID: notification.agentID,
                    agentSessionID: notification.parentAgentSessionID ?? notification.agentSessionID,
                    subject: notification.title ?? notification.agentName, outcome: outcome, at: notification.at,
                    recoveries: [])
            if let note = notification.recovery {
                item.recoveries.append(note)
                recoveries.append(note)
            }
            item.outcome = outcome
            item.at = notification.at
            items[notification.taskID] = item
            since = since ?? notification.at
        }
        guard let since, let last = notifications.last else { return nil }
        self.items = Self.ordered(items.values)
        self.recoveries = recoveries
        lastEntryID = last.id
        self.since = since
    }

    private static func outcome(of notification: HostNotification) -> Item.Outcome? {
        switch notification.kind {
        case .permission: .needsApproval(notification.detail)
        case .question: .asked(notification.detail)
        case .turnFinished: .finished
        case .turnFailed, .limitReached: .failed(notification.detail)
        case .recovered:
            switch notification.recovery?.action {
            case .failed?, .paused?: .failed(notification.recovery?.sentence())
            default: .working
            }
        case .unknown: nil
        }
    }
}
