import SwiftUI

extension SettingsPane.ID {
    static let usage = Self("usage")
    static let notifications = Self("notifications")
}

extension SettingsPane {
    /// Settings › Usage, for `AppSettingsPanes`.
    static func usage(registry: PluginRegistry) -> SettingsPane {
        SettingsPane(
            id: .usage, title: "Usage", systemImage: "gauge.with.dots.needle.33percent", group: .agents, order: 25,
            keywords: ["limits", "rate limit", "quota", "reset", "cost", "tokens", "spend"]
        ) {
            UsageSettingsPage(
                accounts: registry.agents.map { .init(id: $0.id, name: $0.displayName, symbol: $0.symbolName) },
                limits: BuiltInPlugins.usage.limits, reports: BuiltInPlugins.usage.providerReports)
        }
    }

    /// Settings › Notifications, for `AppSettingsPanes`.
    static var notifications: SettingsPane {
        SettingsPane(
            id: .notifications, title: "Notifications", systemImage: "bell.badge", group: .personal, order: 15,
            keywords: ["alerts", "banner", "permission", "question", "finished", "done", "limit"],
            searchEntries: {
                [
                    SettingsSearchEntry(id: NotificationSettingsPage.longWorkRow, title: "When long work finishes", keywords: ["done", "finished"]),
                    SettingsSearchEntry(id: NotificationSettingsPage.thresholdRow, title: "Long means", keywords: ["seconds", "minutes"]),
                    SettingsSearchEntry(id: NotificationSettingsPage.needsYouRow, title: "When a task needs you", keywords: ["permission", "approval", "question"]),
                    SettingsSearchEntry(id: NotificationSettingsPage.limitsRow, title: "Usage limits", keywords: ["reset", "snooze"]),
                ]
            }
        ) {
            NotificationSettingsPage()
        }
    }
}
