import ACP
import SwiftUI

/// Settings › Usage: each agent's account against its limits, and what used it.
struct UsageSettingsPage: View {
    struct Account: Identifiable {
        let id: AgentDefinition.ID
        let name: String
        let symbol: String
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
                    agent: account.id, name: account.name, symbol: account.symbol, limits: limits, reports: reports,
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
