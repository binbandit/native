import Foundation
import NativeHostClient

/// Where task notifications come from: the hosts' notification events (docs/durability.md,
/// "Notifications"), so a task on any host reaches every client and one seen anywhere clears
/// everywhere, or the app's own view of the sessions it follows, as before. One default decides:
/// `NativeHostNotifications`, on unless set off (`-NativeHostNotifications NO` for a run). Sessions
/// that run inside the app, and limits, goals and workflows, notify the old way either way.
enum HostNotificationsSwitch {
    static let defaultsKey = "NativeHostNotifications"
    static let defaultValue = true
    static let history = HostNotificationHistory()

    /// `bool(forKey:)`, since a launch argument (`-NativeHostNotifications YES`) arrives as a string.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) == nil
            ? defaultValue : UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
