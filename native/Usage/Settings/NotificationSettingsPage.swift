import SwiftUI

/// Settings › Notifications: only long work and the moments a task needs you, never about the
/// task you're looking at.
struct NotificationSettingsPage: View {
    static let longWorkRow = SettingsRowID("notifications.longWork")
    static let thresholdRow = SettingsRowID("notifications.threshold")
    static let needsYouRow = SettingsRowID("notifications.needsYou")
    static let limitsRow = SettingsRowID("notifications.limits")
    static let dockBadgeRow = SettingsRowID("notifications.dock-badge")

    @AppStorage(NotificationPreferences.longWorkKey) private var notifiesLongWork = true
    @AppStorage(NotificationPreferences.longWorkSecondsKey) private var longWorkSeconds = NotificationPreferences
        .defaultLongWorkSeconds
    @AppStorage(NotificationPreferences.needsYouKey) private var notifiesNeedsYou = true
    @AppStorage(NotificationPreferences.usageLimitsKey) private var notifiesUsageLimits = true
    @Bindable private var dockBadge = DockBadgePreference.shared

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Notifications",
                description: Text(
                    "Native notifies you only when it’s worth looking: when you’re in another app or another task. Sounds follow Settings › Sounds."
                ))
            SettingsRowGroup {
                SettingsRow(
                    id: Self.longWorkRow, "When long work finishes",
                    description: Text(
                        "With what the turn did, like “Done in 4m · 7 files changed”. When off, finished tasks only show in the sidebar."
                    )
                ) {
                    SettingsSwitch("When long work finishes", isOn: $notifiesLongWork)
                }
                SettingsRow(
                    id: Self.thresholdRow, "Long means", description: Text("Turns shorter than this finish quietly.")
                ) {
                    SettingsSelect(
                        label: "Long means", selection: $longWorkSeconds,
                        options: [30, 60, 120, 300, 600].map {
                            .init(value: $0, title: DSFormat.duration(TimeInterval($0)))
                        })
                }
                .disabled(!notifiesLongWork)
                SettingsRow(
                    id: Self.needsYouRow, "When a task needs you",
                    description: Text(
                        "Permission requests with Allow and Reject, and questions you can answer from the notification. When off, they wait in the task."
                    )
                ) {
                    SettingsSwitch("When a task needs you", isOn: $notifiesNeedsYou)
                }
                SettingsRow(
                    id: Self.limitsRow, "Usage limits",
                    description: Text(
                        "When an agent nears or hits its usage limit, with Resume at Reset, and when a snoozed limit resets. When off, limits show only in the window."
                    )
                ) {
                    SettingsSwitch("Usage limits", isOn: $notifiesUsageLimits)
                }
                SettingsRow(
                    id: Self.dockBadgeRow, "Dock badge",
                    description: Text("Show a count on Native’s icon in the Dock.")
                ) {
                    SettingsSelect(
                        label: "Dock badge", selection: $dockBadge.mode,
                        options: DockBadgePreference.Mode.allCases.map { .init(value: $0, title: $0.title) },
                        width: SettingsMetrics.selectWidth * 1.3)
                }
            }
        }
    }
}
