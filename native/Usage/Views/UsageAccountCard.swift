import ACP
import SwiftUI

/// One provider account in Settings › Usage: each limit window as a bar with its reset time, and
/// what the open tasks have used.
struct UsageAccountCard: View {
    let agent: AgentDefinition.ID
    let name: String
    let symbol: String
    let limits: UsageLimits
    let reports: ProviderUsageReports

    var body: some View {
        let status = reports.status(of: agent)
        Card {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header(status)
                TimelineView(.everyMinute) { context in
                    windows(status, now: context.date)
                }
                tasks
            }
        }
    }

    private func header(_ status: ProviderUsageReports.Status) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: symbol)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: DS.Size.rowLeading)
            Text(name)
                .font(.dsHeadline)
                .foregroundStyle(.dsTextPrimary)
            if let report = reports.reports[agent] {
                Text("Read \(report.capturedAt.formatted(.relative(presentation: .named)))")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            Spacer(minLength: DS.Space.md)
            if status == .refreshing {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                    .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
            } else if status != .unavailable {
                IconButton("Read \(name)’s Limits Again", systemImage: "arrow.clockwise") {
                    Task { await reports.refresh(agent) }
                }
            }
        }
    }

    @ViewBuilder
    private func windows(_ status: ProviderUsageReports.Status, now: Date) -> some View {
        if let report = reports.reports[agent] {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                ForEach(report.windows) { window in
                    UsageMeter(title: window.name, fraction: window.utilization, detail: window.resetsAt.map { reset($0, now: now) })
                }
            }
        } else if let limit = limits.limitStatus(for: agent) {
            // What the agent last said when it neared or hit a limit.
            UsageMeter(
                title: limit.limitName.prefix(1).uppercased() + limit.limitName.dropFirst(),
                fraction: limit.utilization ?? (limit.level == .reached ? 1 : 0),
                detail: limit.resetsAt.map { reset($0, now: now) })
        } else {
            Text(explanation(status))
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var tasks: some View {
        let spend = reports.taskUsage(of: agent)
        if !spend.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ContributorSectionHeader(title: "Open tasks", tokens: totalCost(spend))
                ForEach(spend) { task in
                    ContributorRow(
                        title: task.title,
                        detail: "\(DSFormat.tokens(task.contextUsed)) of \(DSFormat.tokens(task.contextSize)) context",
                        tokens: task.cost.map { $0.amount.formatted(.currency(code: $0.currency)) } ?? "–")
                }
            }
        }
    }

    private func reset(_ date: Date, now: Date) -> String {
        "Resets \(DSFormat.time(date, now: now))"
    }

    private func totalCost(_ spend: [UsageTaskSpend]) -> String {
        let costs = spend.compactMap(\.cost)
        guard let currency = costs.first?.currency else { return "" }
        return costs.reduce(0) { $0 + $1.amount }.formatted(.currency(code: currency))
    }

    private func explanation(_ status: ProviderUsageReports.Status) -> String {
        switch status {
        case .unavailable: "Open a \(name) task to read where its limits stand. Reading them costs nothing."
        case .unreported: "\(name) doesn’t report its usage limits."
        case .ready, .refreshing: "Reading \(name)’s limits…"
        }
    }
}
