import Experiments
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
            var entries = [
                SettingsSearchEntry(
                    id: GeneralSettingsPage.followUpRow,
                    title: "Follow-up behavior",
                    description: "Queue messages to send after the agent finishes, or steer the agent mid-turn.",
                    keywords: ["queue", "steer", "return", "send", "message"], plainly: .followUp
                )
            ]
            if ExperimentStore.shared.value(of: .homeNext) {
                entries += HomeNextSettingsSection.searchEntries
            }
            #if os(macOS)
            entries.append(GitHubAccountsSettingsSection.searchEntry)
            #endif
            return entries
        },
        content: { GeneralSettingsPage() }
    )
}

struct GeneralSettingsPage: View {
    @Environment(\.settingsPlainly) private var plainly
    @Environment(SettingsPresentation.self) private var presentation
    @Environment(DockBadgePreference.self) private var injectedBadge: DockBadgePreference?
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?
    @Experiment(.homeNext) private var homeNext
    private let badgePreference: DockBadgePreference

    init(dockBadge: DockBadgePreference = .shared) {
        self.badgePreference = dockBadge
    }

    static var badgeEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: NotificationSettingsPage.dockBadgeRow, title: "Badge", keywords: ["dock", "unread", "count"])
    }

    static let followUpRow = SettingsRowID("general.follow-up")

    @AppStorage(FollowUpBehavior.storageKey) private var followUp = FollowUpBehavior.defaultValue

    var body: some View {
        @Bindable var dockBadge = injectedBadge ?? badgePreference
        SettingsPage {
            SettingsHeader(
                "General", plainly: .init(title: "General", description: "How Native behaves while you work."))
            if plainly {
                SettingsGroup(
                    title: "While an agent works",
                    footer: followUpHint
                ) {
                    followUpControl
                }
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    SettingsGroup(title: "Dock") {
                        SettingsRow(id: NotificationSettingsPage.dockBadgeRow, "Badge") {
                            SettingsSelect(
                                label: "Badge", selection: $dockBadge.mode,
                                options: DockBadgePreference.Mode.allCases.map {
                                    .init(value: $0, title: $0 == .needsYouOrUnread ? "Need you or unread" : $0.title)
                                }, width: DS.Settings.wideControl, isDefault: dockBadge.mode == .needsYou)
                        }
                    }
                    HStack(spacing: DS.Space.xs) {
                        Text("What a new task starts with is in")
                        Button {
                            presentation.open(.newTasks)
                        } label: {
                            Text("New Tasks").underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .font(DS.Settings.caption)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(.horizontal, DS.Settings.rowInset)
                }
            } else {
                SettingsRowGroup { followUpControl }
            }
            if homeNext {
                HomeNextSettingsSection()
            }
            #if os(macOS)
            if let gitHub {
                GitHubAccountsSettingsSection().environment(gitHub)
            }
            #endif
        }
    }

    private var followUpControl: some View {
        SettingsRow(
            id: Self.followUpRow, "Follow-up behavior", plainly: .followUp,
            description: Text("Queue messages to send after the agent finishes, or steer the agent mid-turn."),
            detail: plainly
                ? nil
                : Text(
                    "Use \(Image(systemName: "command"))\(Image(systemName: "arrow.turn.down.left")) to \(followUp.opposite.title.lowercased()). Agents that can't steer queue instead."
                )
        ) {
            SettingsSelect(
                label: "Follow-up behavior", selection: $followUp,
                options: FollowUpBehavior.allCases.map {
                    .init(
                        value: $0,
                        title: plainly
                            ? ($0 == .steer ? "Steer: add to the turn" : "Queue: send when it's done") : $0.title)
                }, width: plainly ? DS.Settings.wideControl : SettingsMetrics.selectWidth,
                isDefault: followUp == FollowUpBehavior.defaultValue)
        }
    }

    private var followUpHint: String {
        let alternate =
            followUp == .steer
            ? "⌘Return queues your message until the turn finishes."
            : "⌘Return steers the agent between steps."
        return
            "Steering lets the agent change course between steps. \(alternate) Agents that can't be steered always queue."
    }

}

#if DEBUG
#Preview("General settings") {
    DSPreviewPair {
        GeneralSettingsPage()
            .settingsPreviewPage()
    }
    .environment(SettingsPresentation())
    .environment(GitHubAccountPreviewFixtures.model(.single))
    .defaultAppStorage(PreviewUserDefaults())
}

#Preview("General settings - Narrow") {
    DSPreviewPair {
        GeneralSettingsPage()
            .settingsPreviewPage(width: 420)
    }
    .environment(SettingsPresentation())
    .environment(GitHubAccountPreviewFixtures.model(.longName))
    .defaultAppStorage(PreviewUserDefaults())
}

#Preview("Plainly - General") {
    DSPreviewPair {
        GeneralSettingsPage(dockBadge: DockBadgePreference(defaults: PreviewUserDefaults())).settingsPreviewPage()
    }
    .environment(SettingsPresentation())
    .environment(GitHubAccountPreviewFixtures.model(.multiple))
    .environment(\.settingsPlainly, true)
    .defaultAppStorage(PreviewUserDefaults())
}
#endif
