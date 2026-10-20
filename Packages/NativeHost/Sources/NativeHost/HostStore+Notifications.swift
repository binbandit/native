import Foundation
import NativeHostProtocol

// The notification backlog (`HostCore+Notifications.swift`): every notification the host posted,
// newest kept, with whether it's still news. A row holds the notification as JSON; its id and state
// live in columns too, since that's what the host looks them up and changes them by.
extension HostStore {
    /// Created by the schema's version 6 step.
    static let notificationsTable = """
        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            state TEXT NOT NULL,
            body TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS notifications_state ON notifications(state);
        """

    /// Adds a notification, numbered after every one before it (also ones since dropped), and drops
    /// the oldest beyond `limit`. Returns it with its id.
    func addNotification(_ notification: HostNotification, keeping limit: Int) throws -> HostNotification {
        try transaction {
            try database.run(
                "INSERT INTO notifications (session_id, state, body) VALUES (?, ?, ?)",
                .text(notification.sessionID.description), .text(notification.state.rawValue),
                try JSONColumn.encode(notification))
            var stored = notification
            stored.id = database.lastInsertRowID
            try database.run(
                "DELETE FROM notifications WHERE id <= ?", .integer(stored.id - Int64(max(limit, 1))))
            return stored
        }
    }

    /// Those numbered after `id`, oldest first.
    func notifications(after id: Int64?, limit: Int) throws -> [HostNotification] {
        try database.query(
            "SELECT id, state, body FROM notifications WHERE id > ? ORDER BY id LIMIT ?", .integer(id ?? 0),
            .integer(Int64(limit))
        ).compactMap(Self.notification(row:))
    }

    /// Every notification that's still news, oldest first.
    func activeNotifications() throws -> [HostNotification] {
        try database.query(
            "SELECT id, state, body FROM notifications WHERE state = ? ORDER BY id",
            .text(HostNotification.State.active.rawValue)
        ).compactMap(Self.notification(row:))
    }

    func notification(_ id: Int64) throws -> HostNotification? {
        try database.query("SELECT id, state, body FROM notifications WHERE id = ?", .integer(id)).first
            .flatMap(Self.notification(row:))
    }

    /// The newest id handed out, whether or not that notification is still kept.
    func latestNotificationID() throws -> Int64? {
        try database.query("SELECT seq FROM sqlite_sequence WHERE name = 'notifications'").first?.first?.integer
    }

    /// Writes back notifications whose state changed, together.
    func updateNotifications(_ notifications: [HostNotification]) throws {
        guard !notifications.isEmpty else { return }
        try transaction {
            for notification in notifications {
                try database.run(
                    "UPDATE notifications SET state = ?, body = ? WHERE id = ?", .text(notification.state.rawValue),
                    try JSONColumn.encode(notification), .integer(notification.id))
            }
        }
    }

    private static func notification(row: [SQLiteDatabase.Value]) -> HostNotification? {
        guard let id = row[0].integer, var notification = JSONColumn.decode(HostNotification.self, row[2]) else {
            return nil
        }
        notification.id = id
        notification.state = row[1].text.map { HostNotification.State(rawValue: $0) ?? .unknown } ?? .unknown
        return notification
    }
}
