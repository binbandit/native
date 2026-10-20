import Foundation
import NativeHostProtocol

// The host's notifications (docs/durability.md, "Notifications"): catching up on them, saying which
// the user saw, and doing what the user picked on one.
extension NativeHostClient {
    /// Notifications after `after`, oldest first, plus every one still active.
    public func notifications(after: Int64? = nil, limit: Int = 200) async throws -> HostNotificationList {
        try await call(HostProtocol.Method.listNotifications, ListNotificationsParams(after: after, limit: limit))
    }

    /// The user saw these here; every other client takes them down.
    public func acknowledgeNotifications(_ ids: [Int64]) async throws {
        guard !ids.isEmpty else { return }
        let _: EmptyMessage = try await call(
            HostProtocol.Method.acknowledgeNotifications, AcknowledgeNotificationsParams(ids: ids))
    }

    /// Does what the user picked on a notification (allow, reject, reply) on the host, which
    /// acknowledges it too.
    public func act(
        on notification: Int64, _ action: HostNotification.Action, text: String? = nil
    ) async throws -> ActOnNotificationResult.Outcome {
        let result: ActOnNotificationResult = try await call(
            HostProtocol.Method.actOnNotification, ActOnNotificationParams(id: notification, action: action, text: text)
        )
        return result.outcome
    }
}
