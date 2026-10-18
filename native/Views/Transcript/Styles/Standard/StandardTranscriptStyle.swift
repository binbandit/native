import ACP
import SwiftUI

/// The default transcript, Factory style: agent replies and tool activity in one column, tool
/// activity as one dense block, and the user's prompts in trailing bubbles. The turn that's running
/// (or ran last) keeps every row; earlier turns fold their tool work into one line.
nonisolated struct StandardTranscriptStyle: TranscriptStyle {
    @MainActor func makeBody(_ transcript: TranscriptStyleConfiguration) -> some View {
        StandardTranscript(transcript: transcript)
    }
}

private struct StandardTranscript: View {
    let transcript: TranscriptStyleConfiguration

    @AppStorage(TranscriptPreferences.foldsEarlierTurnsKey) private var foldsEarlierTurns = true
    /// Earlier turns the user opened back up.
    @State private var unfoldedTurns: Set<TranscriptTurn.ID> = []

    var body: some View {
        let lines = StandardTranscriptLine.plan(transcript, folding: foldsEarlierTurns, unfolded: unfoldedTurns)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                self.line(line)
                    .padding(.top, line.spacing)
            }
            if transcript.isWorking {
                WorkingIndicator()
                    .padding(.top, DS.Space.xl)
            }
        }
    }

    @ViewBuilder private func line(_ line: StandardTranscriptLine) -> some View {
        switch line.kind {
        case .row(let row, let itemIndex):
            self.row(row, itemIndex: itemIndex)
        case .fold(let turn, let summary, let isUnfolded):
            TurnActivityFold(summary: summary, isUnfolded: isUnfolded) {
                withAnimation(.reveal) {
                    if isUnfolded {
                        unfoldedTurns.remove(turn.id)
                    } else {
                        unfoldedTurns.insert(turn.id)
                    }
                }
            }
        case .footer(let turn, let summary, let ending, let showsChanges):
            TurnFooter(
                turn: turn, summary: summary, ending: ending, showsChanges: showsChanges,
                subagents: subagents(in: turn), openSubagent: transcript.openSubagent)
        case .changes(let summary):
            TurnChangesCard(summary: summary)
        case .usageLimit(let stop, let isLatestTurn):
            UsageLimitTranscriptCard(session: transcript.session, stop: stop, isLatestTurn: isLatestTurn)
        }
    }

    @ViewBuilder private func row(_ row: TranscriptRow, itemIndex: Int) -> some View {
        switch row {
        case .exploration(let calls):
            transcript.exploration(calls)
        case .item(.message(let message)):
            let thinking = transcript.session.state.thinkingInterval(at: itemIndex)
            MessageView(message: message, thinking: thinking.map { ThinkingClock(start: $0.start, end: $0.end) })
                .equatable()
        case .item(.toolCall(let call)):
            transcript.toolCall(call)
        case .item(.notice(let notice)):
            NoticeView(notice: notice)
        case .item(.subagent(let subagent)):
            transcript.subagent(subagent)
        case .item(.sessionMessage(let message)):
            transcript.sessionMessage(message)
        }
    }

    private func subagents(in turn: TranscriptTurn) -> [SubagentState] {
        transcript.session.state.items[turn.items].compactMap { item in
            if case .subagent(let subagent) = item { subagent } else { nil }
        }
    }
}

extension TranscriptRow {
    /// Tool calls and folded runs of them.
    var isToolActivity: Bool {
        switch self {
        case .exploration, .item(.toolCall): true
        default: false
        }
    }
}

private struct WorkingIndicator: View {
    var body: some View {
        HStack(spacing: DS.Space.md) {
            DotGridLoader(pattern: .typing)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            Text("Working…")
        }
        .font(.dsCallout)
        .foregroundStyle(.dsTextSecondary)
    }
}
