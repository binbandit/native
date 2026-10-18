import Foundation
import NativeHostProtocol
import UserNotifications

/// Local notifications while the app runs. Push (APNs) and Live Activities come once there's a
/// developer team: they'll post the same categories from the host, threaded per host so hosts never
/// mix (`docs/companion.md`, "Notifications").
enum CompanionNotifications {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func postUpdateAvailable(hostName: String, hostID: HostID, version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Update available on \(hostName)"
        content.body = "Native \(version) is ready to install. Open the host to see what's new."
        // One thread per host: notifications from different hosts never group together.
        content.threadIdentifier = "host.\(hostID)"
        content.userInfo = ["hostID": hostID.description]
        let request = UNNotificationRequest(identifier: "update.\(hostID).\(version)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
