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
    let activity: ActivityLog

    /// The longest limit window providers have, so the projects cover all of it.
    private static let recentDays = 7

    var body: some View {
        let status = reports.status(of: agent)
        Card {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header(status)
                TimelineView(.everyMinute) { context in
                    windows(status, now: context.date)
                }
                recentProjects
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
                    UsageMeter(
                        title: window.name, fraction: window.utilization,
                        detail: window.resetsAt.map { reset($0, now: now) })
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

    /// What used the account lately, project by project, from what Native counted.
    @ViewBuilder
    private var recentProjects: some View {
        let start = Calendar.current.date(byAdding: .day, value: 1 - Self.recentDays, to: .now) ?? .now
        let usage = activity.projectUsage(of: agent.rawValue, since: start).filter { !$0.counts.isEstimate }
        if !usage.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ContributorSectionHeader(
                    title: "Past \(Self.recentDays) days",
                    tokens: spent(usage.reduce(ActivityCounts()) { $0 + $1.counts }))
                ForEach(usage, id: \.project) { entry in
                    ContributorRow(
                        title: URL(filePath: entry.project).lastPathComponent, detail: summary(of: entry.counts),
                        tokens: spent(entry.counts))
                }
            }
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

    /// "12 prompts · 1h 4m of agent time"
    private func summary(of counts: ActivityCounts) -> String {
        let prompts = ActivityMetric.prompts.describe(Double(counts.prompts))
        guard counts.activeSeconds > 0 else { return prompts }
        return "\(prompts) · \(DSFormat.duration(counts.activeSeconds)) of agent time"
    }

    /// Cost when the agent reports it, tokens otherwise.
    private func spent(_ counts: ActivityCounts) -> String {
        counts.cost > 0
            ? ActivityMetric.cost.describe(counts.cost) : ActivityMetric.tokens.describe(Double(counts.tokens))
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
