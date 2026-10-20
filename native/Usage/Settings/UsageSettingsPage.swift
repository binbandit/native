import ACP
import SwiftUI

/// Settings › Usage: each agent's account against its limits, and what used it.
struct UsageSettingsPage: View {
    struct Account: Identifiable {
        let id: AgentDefinition.ID
        let name: String
        /// For the agent's icon.
        let definition: AgentDefinition
    }

    let accounts: [Account]
    let limits: UsageLimits
    let reports: ProviderUsageReports
    let activity: ActivityLog
    let opener: (ActivityDay.Task) -> (() -> Void)?

    /// Readings older than this are taken again when the page opens.
    private static let staleAfter: TimeInterval = 5 * 60

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Usage",
                description: Text(
                    "Your year with agents, and where each agent’s account stands against its usage limits, read from the agent itself."
                ))
            UsageActivityCard(activity: activity, opener: opener)
            if accounts.isEmpty {
                EmptyStateView(
                    "No agents yet", systemImage: "gauge.with.dots.needle.33percent",
                    message: "Agents you add show their limits here.")
            }
            ForEach(accounts) { account in
                UsageAccountCard(
                    agent: account.id, name: account.name, definition: account.definition, limits: limits,
                    reports: reports,
                    activity: activity)
            }
        }
        .task {
            activity.refreshBackfill()
            for account in accounts where reports.status(of: account.id) == .ready {
                let isStale =
                    reports.reports[account.id].map { Date.now.timeIntervalSince($0.capturedAt) > Self.staleAfter }
                    ?? true
                if isStale {
                    await reports.refresh(account.id)
                }
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Usage settings") {
    let app = AppModel.preview()
    DSPreviewPair {
        UsageSettingsPage(
            accounts: app.agents.prefix(2).map {
                UsageSettingsPage.Account(id: $0.agent.id, name: $0.agent.displayName, definition: $0.agent)
            },
            limits: UsagePreviewFixtures.limits(), reports: UsagePreviewFixtures.reports,
            activity: UsagePreviewFixtures.activity(), opener: { _ in nil }
        )
        .settingsPreviewPage()
    }
    .environment(SettingsPresentation())
}

#Preview("Usage settings - No agents") {
    DSPreviewPair {
        UsageSettingsPage(
            accounts: [], limits: UsagePreviewFixtures.clearLimits(), reports: ProviderUsageReports(),
            activity: UsagePreviewFixtures.activity(empty: true), opener: { _ in nil }
        )
        .settingsPreviewPage()
    }
    .environment(SettingsPresentation())
}
#endif
