import ACP
import SwiftUI

/// What fills a session's context window, sized for a popover: the totals and cost, the window as
/// a bar with its categories, and the parts of the user's setup that take the most. Agents that
/// can't break their context down get the totals and a plain account of why there's no more.
struct ContextBreakdownView<Source: ContextSource>: View {
    let source: Source

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ContextBreakdownHeader(source: source)
                .padding(DS.Space.lg)
            SeparatorLine()
            CappedHeightScrollView(maxHeight: UsageMetrics.breakdownMaxHeight) {
                content
                    .padding(DS.Space.lg)
            }
        }
        .frame(width: UsageMetrics.breakdownWidth)
        .task {
            // Reading the breakdown is free and quick, so an out-of-date one is replaced on open.
            if case .ready(let isStale) = source.reportStatus, source.report == nil || isStale {
                await source.refreshReport()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let report = source.report {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                ContextBar(composition: ContextComposition(report: report))
                ContextCategoryTable(composition: ContextComposition(report: report))
                if report.hasContributors {
                    SeparatorLine()
                    ContextContributors(report: report)
                }
            }
            // While a fresh report is read, the last one stays put, dimmed, rather than jumping.
            .opacity(source.reportStatus == .refreshing ? 0.5 : 1)
            .animation(.dsStandard, value: source.reportStatus)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                if let usage = source.usage, usage.size > 0 {
                    ContextBar(composition: ContextComposition(used: usage.used, window: usage.size))
                }
                ContextBreakdownPlaceholder(source: source)
            }
        }
    }
}

/// Why there's no breakdown to show, and what will bring one.
private struct ContextBreakdownPlaceholder<Source: ContextSource>: View {
    let source: Source

    var body: some View {
        switch source.reportStatus {
        case .unsupported:
            note(systemImage: "info.circle", text: source.usage == nil
                ? "\(source.agentName) hasn’t reported its context yet. The total shows up after its first reply."
                : "\(source.agentName) reports only how much of its context is in use, not what fills it.")
        case .busy:
            note(systemImage: "clock", text: "The breakdown is read while \(source.agentName) is idle, at no token cost. It’s ready when this turn ends.")
        case .refreshing, .ready:
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                Text("Reading what fills the context…")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: DS.Space.md) {
                note(systemImage: "exclamationmark.triangle", text: "\(source.agentName) didn’t answer with a breakdown.")
                Button("Try Again") {
                    Task { await source.refreshReport() }
                }
                .buttonStyle(.ds(.secondary))
            }
        }
    }

    private func note(systemImage: String, text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.dsTextTertiary)
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextSecondary)
    }
}
