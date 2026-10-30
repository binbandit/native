import ACP
import SwiftUI

/// The breakdown's top: how full the window is in numbers, what the session has cost, which model,
/// how fresh the breakdown is, and a next step when the window is nearly full.
struct ContextBreakdownHeader<Source: ContextSource>: View {
    let source: Source

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Context")
                        .font(.dsHeadline)
                        .foregroundStyle(.dsTextPrimary)
                    DSMinuteTimeline { now in
                        Text(subtitle(now: now))
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                refreshButton
            }
            if source.isAwaitingContextUsage {
                Text("Compacted")
                    .font(.dsTitle2)
                    .foregroundStyle(.dsTextPrimary)
            } else if let totals {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text(DSFormat.percent(totals.fraction))
                        .font(.dsTitle2)
                        .foregroundStyle(.dsTextPrimary)
                        .contentTransition(.numericText(value: totals.fraction))
                    Text("\(DSFormat.tokens(totals.used)) of \(DSFormat.tokens(totals.window)) tokens")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                    Spacer(minLength: DS.Space.md)
                    if let cost = source.usage?.cost {
                        Text("\(cost.amount, format: .currency(code: cost.currency)) spent")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                            .help("What this task has cost so far, as \(source.agentName) estimates it")
                    }
                }
                .monospacedDigit()
                if let overLimit = source.report?.overLimit {
                    Text(overLimit)
                        .font(.dsCaption)
                        .foregroundStyle(.dsDanger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let summary = ContextPressure(fraction: totals.fraction).summary {
                    pressureNote(summary)
                }
            }
        }
    }

    /// The breakdown's own numbers while it's current; otherwise the agent's latest usage update,
    /// which follows every turn.
    private var totals: (used: Int, window: Int, fraction: Double)? {
        if let report = source.report, source.reportStatus != .ready(isStale: true), report.windowTokens > 0 {
            return (report.usedTokens, report.windowTokens, report.fractionUsed)
        }
        guard let usage = source.usage, usage.size > 0 else { return nil }
        return (usage.used, usage.size, usage.fractionUsed)
    }

    private func subtitle(now: Date) -> String {
        guard let report = source.report else { return source.agentName }
        let age =
            now.timeIntervalSince(report.capturedAt) < 60
            ? "just now" : report.capturedAt.formatted(.relative(presentation: .named))
        return [report.model ?? source.agentName, "updated \(age)"].joined(separator: " · ")
    }

    @ViewBuilder
    private var refreshButton: some View {
        if source.reportStatus == .refreshing {
            DotGridLoader(pattern: .typing)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                .accessibilityLabel("Reading the breakdown")
        } else if source.reportStatus != .unsupported {
            IconButton("Read the Breakdown Again", systemImage: "arrow.clockwise") {
                Task { await source.refreshReport() }
            }
            .disabled(!source.reportStatus.canRefresh)
        }
    }

    private func pressureNote(_ summary: String) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.dsWarning)
            Text("\(summary). \(source.agentName) compacts on its own when it runs out of room.")
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if source.canCompact {
                Button("Compact Now") {
                    Task { await source.compact() }
                }
                .buttonStyle(.ds(.secondary))
                .disabled(source.reportStatus == .busy)
                .help("Summarizes the conversation so far to free up room, as /compact does")
            }
        }
        .font(.dsCaption)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Breakdown header") {
    var refreshing = PreviewContextSource.claude(used: 925_000)
    refreshing.reportStatus = .refreshing
    return DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            ContextBreakdownHeader(source: PreviewContextSource.claude(used: 240_000))
            ContextBreakdownHeader(source: refreshing)
            ContextBreakdownHeader(source: PreviewContextSource.codex)
        }
        .frame(width: 360)
    }
}
#endif

#if DEBUG
#Preview("Context header after compaction") {
    DSPreviewPair {
        ContextBreakdownHeader(source: PreviewContextSource.compacted)
            .padding(DS.Space.lg)
            .frame(width: UsageMetrics.breakdownWidth)
    }
}
#endif
