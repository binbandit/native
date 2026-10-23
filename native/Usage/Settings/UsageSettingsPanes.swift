import SwiftUI

extension SettingsPane.ID {
    static let usage = Self("usage")
    static let notifications = Self("notifications")
}

extension SettingsPane {
    /// Settings › Usage, for `AppSettingsPanes`.
    static func usage(registry: PluginRegistry) -> SettingsPane {
        SettingsPane(
            id: .usage, title: "Usage", systemImage: "gauge.with.dots.needle.33percent", group: .agents, order: 24,
            keywords: [
                "limits", "rate limit", "quota", "reset", "cost", "tokens", "spend", "activity", "streak", "graph",
            ]
        ) {
            UsageSettingsPage(
                accounts: registry.agents.map { .init(id: $0.id, name: $0.displayName, definition: $0) },
                limits: BuiltInPlugins.usage.limits, reports: BuiltInPlugins.usage.providerReports,
                activity: BuiltInPlugins.usage.activity, opener: BuiltInPlugins.usage.opener)
        }
    }

    /// Settings › Notifications, for `AppSettingsPanes`.
    static var notifications: SettingsPane {
        SettingsPane(
            id: .notifications, title: "Notifications", systemImage: "bell.badge", group: .personal, order: 15,
            keywords: ["alerts", "banner", "permission", "question", "finished", "done", "limit"],
            searchEntries: {
                [
                    SettingsSearchEntry(
                        id: NotificationSettingsPage.longWorkRow, title: "When long work finishes",
                        keywords: ["done", "finished"], plainly: .longWork),
                    SettingsSearchEntry(
                        id: NotificationSettingsPage.thresholdRow, title: "Long means",
                        keywords: ["seconds", "minutes"], plainly: .threshold),
                    SettingsSearchEntry(
                        id: NotificationSettingsPage.needsYouRow, title: "When a task needs you",
                        keywords: ["permission", "approval", "question"], plainly: .needsYou),
                    SettingsSearchEntry(
                        id: NotificationSettingsPage.limitsRow, title: "Usage limits", keywords: ["reset", "snooze"],
                        plainly: .limits),
                    SettingsSearchEntry(
                        id: NotificationSettingsPage.dockBadgeRow, title: "Dock badge",
                        keywords: ["dock", "badge", "icon", "count", "unread"]),
                ]
            }
        ) {
            NotificationSettingsPage()
        }
    }
}
