import Foundation
import NativeHostProtocol

/// Notification cursors and the transition from the activity journal to host notifications.
@MainActor
public final class HostNotificationHistory {
    public static let defaultsKey = "NativeHostSeenNotifications"

    private let defaults: UserDefaults
    // Catch-up can save the new cursor before the journal finishes reading the previous absence.
    private let hostsSeenAtLaunch: Set<String>
    private var cursors: [String: Int64]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Foundation's numeric property-list values bridge differently on Apple platforms and Linux.
        cursors =
            defaults.dictionary(forKey: Self.defaultsKey)?.compactMapValues { ($0 as? NSNumber)?.int64Value } ?? [:]
        hostsSeenAtLaunch = Set(cursors.keys)
    }

    public func usesHostNotifications(on host: HostInfo, enabled: Bool) -> Bool {
        enabled && host.notificationEvents == true
    }

    /// The journal bridges the first enabled launch of a previously known host. Its caller still
    /// requires an activity cursor, so a genuinely new host only establishes its baseline.
    public func usesActivitySummary(on host: HostInfo, enabled: Bool) -> Bool {
        !usesHostNotifications(on: host, enabled: enabled) || !hostsSeenAtLaunch.contains(host.hostID.description)
    }

    public func lastSeen(on host: HostID) -> Int64? {
        cursors[host.description]
    }

    public func remember(_ id: Int64, on host: HostID) {
        guard id > cursors[host.description] ?? -1 else { return }
        cursors[host.description] = id
        defaults.set(cursors, forKey: Self.defaultsKey)
    }
}
