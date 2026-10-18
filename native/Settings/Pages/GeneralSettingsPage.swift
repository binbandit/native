import SwiftUI

extension SettingsPane.ID {
    static let general = Self("general")
}

extension SettingsPane {
    static let general = SettingsPane(
        id: .general,
        title: "General",
        systemImage: "slider.horizontal.3",
        group: .personal,
        order: 0,
        searchEntries: {
            [
                SettingsSearchEntry(
                    id: GeneralSettingsPage.followUpRow,
                    title: "Follow-up behavior",
                    description: "Queue messages to send after the agent finishes, or steer the agent mid-turn.",
                    keywords: ["queue", "steer", "return", "send", "message"]
                ),
                SettingsSearchEntry(
                    id: GeneralSettingsPage.dockBadgeRow,
                    title: "Dock badge",
                    description: "Show how many tasks need you on Native's icon in the Dock.",
                    keywords: ["dock", "badge", "icon", "count", "unread", "needs you"]
                ),
            ]
        },
        content: { GeneralSettingsPage() }
    )
}

struct GeneralSettingsPage: View {
    static let followUpRow = SettingsRowID("general.follow-up")
    static let dockBadgeRow = SettingsRowID("general.dock-badge")

    @AppStorage(FollowUpBehavior.storageKey) private var followUp = FollowUpBehavior.defaultValue
    @Bindable private var dockBadge = DockBadgePreference.shared

    var body: some View {
        SettingsPage {
            SettingsHeader("General")
            SettingsRowGroup {
                SettingsRow(
                    id: Self.followUpRow,
                    "Follow-up behavior",
                    description: Text("Queue messages to send after the agent finishes, or steer the agent mid-turn."),
                    detail: Text(
                        "Use \(Image(systemName: "command"))\(Image(systemName: "arrow.turn.down.left")) to \(followUp.opposite.title.lowercased()). Agents that can't steer queue instead."
                    )
                ) {
                    SettingsSelect(
                        label: "Follow-up behavior",
                        selection: $followUp,
                        options: FollowUpBehavior.allCases.map { .init(value: $0, title: $0.title) }
                    )
                }
                SettingsRow(
                    id: Self.dockBadgeRow,
                    "Dock badge",
                    description: Text("Show how many tasks need you on Native's icon in the Dock.")
                ) {
                    SettingsSelect(
                        label: "Dock badge",
                        selection: $dockBadge.mode,
                        options: DockBadgePreference.Mode.allCases.map { .init(value: $0, title: $0.title) }
                    )
                }
            }
        }
    }
}
