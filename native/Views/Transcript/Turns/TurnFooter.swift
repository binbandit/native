import ACP
import SwiftUI

/// The quiet line that closes a finished turn: how it ended if not normally, how long it took,
/// what it changed and the agents it started. "Stopped · 1m 12s · 7 files changed +120 −14".
struct TurnFooter: View {
    let turn: TranscriptTurn
    let summary: TurnSummary
    /// The notice a turn that didn't end normally closed with.
    let ending: TranscriptNotice?
    /// Whether to list the changed files here; the latest turn shows them in its own card.
    let showsChanges: Bool
    let subagents: [SubagentState]
    let openSubagent: (SessionID) -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text(verbatim: "·")
                        .foregroundStyle(.dsTextQuaternary)
                        .accessibilityHidden(true)
                }
                view(for: part)
            }
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextTertiary)
        .accessibilityElement(children: .contain)
    }

    private enum Part {
        case ending(TranscriptNotice)
        case duration(Date, Date)
        case changes
        case agents
    }

    private var parts: [Part] {
        var parts: [Part] = []
        if let ending { parts.append(.ending(ending)) }
        if let start = turn.startedAt, let end = turn.endedAt { parts.append(.duration(start, end)) }
        if showsChanges, !summary.changedFiles.isEmpty { parts.append(.changes) }
        if !subagents.isEmpty { parts.append(.agents) }
        return parts
    }

    @ViewBuilder private func view(for part: Part) -> some View {
        switch part {
        case .ending(let notice):
            Label(
                notice.text.trimmingSuffix("."),
                systemImage: notice.isError ? "exclamationmark.triangle" : "stop.circle"
            )
            .foregroundStyle(notice.isError ? .dsDanger : .dsTextSecondary)
            .textSelection(.enabled)
        case .duration(let start, let end):
            ElapsedTimeText(since: start, until: end)
        case .changes:
            HStack(spacing: DS.Space.xs) {
                Text(TurnChangesCard.title(for: summary))
                DiffStatsText(stats: DiffStats(added: summary.linesAdded, removed: summary.linesRemoved))
            }
        case .agents:
            SubagentCountChip(subagents: subagents, open: openSubagent)
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
