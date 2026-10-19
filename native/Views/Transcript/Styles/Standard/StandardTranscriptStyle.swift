import ACP
import SwiftUI

/// The default transcript: agent replies and tool activity in one column, tool
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
    /// The line a search result opened at, highlighted for a moment.
    @State private var revealedLine: StandardTranscriptLine.ID?
    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?

    var body: some View {
        let lines = StandardTranscriptLine.plan(transcript, folding: foldsEarlierTurns, unfolded: unfoldedTurns)
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    self.line(line)
                        .background {
                            if line.id == revealedLine {
                                RoundedRectangle(cornerRadius: DS.Radius.card)
                                    .fill(Color.dsAccentSubtle)
                                    .padding(-DS.Space.sm)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.top, line.spacing)
                }
                if transcript.isWorking {
                    WorkingIndicator(quietSince: transcript.session.state.quietSince)
                        .padding(.top, DS.Space.xl)
                }
            }
            .task(id: transcript.session.transcriptReveal) {
                await reveal(transcript.session.transcriptReveal, with: proxy)
            }
        }
    }

    /// Scrolls to the line showing the requested item (unfolding its turn first) and highlights it.
    private func reveal(_ request: TranscriptReveal?, with proxy: ScrollViewProxy) async {
        guard let request else { return }
        defer {
            // Done with it, unless a newer request replaced it meanwhile.
            if transcript.session.transcriptReveal == request {
                transcript.session.transcriptReveal = nil
            }
        }
        let state = transcript.session.state
        guard let index = state.items.firstIndex(where: { $0.id == request.itemID }) else { return }
        if let turn = state.turns.first(where: { $0.items.contains(index) }) {
            unfoldedTurns.insert(turn.id)
        }
        // Let the unfolded rows lay out before scrolling to one of them.
        try? await Task.sleep(for: .milliseconds(80))
        let lines = StandardTranscriptLine.plan(transcript, folding: foldsEarlierTurns, unfolded: unfoldedTurns)
        let line = lines.first { line in
            switch line.kind {
            case .row(let row, let start): (start..<start + row.itemCount).contains(index)
            case .replySection(_, _, let start): start == index
            case .activityRun(let run): run.items.indices.contains(index)
            default: false
            }
        }
        guard let line else { return }
        if case .activityRun(let run) = line.kind {
            disclosures?.openRun(run.id)
        }
        withAnimation(.dsStandard) {
            proxy.scrollTo(line.id, anchor: .center)
            revealedLine = line.id
        }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation(.dsStandard) {
            revealedLine = nil
        }
    }

    @ViewBuilder private func line(_ line: StandardTranscriptLine) -> some View {
        switch line.kind {
        case .row(let row, let itemIndex):
            self.row(row, itemIndex: itemIndex)
        case .replySection(let source, let isFirst, _):
            MarkdownSectionView(source: source, isFirst: isFirst)
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .activityRun(let run):
            ToolRunView(run: run, session: transcript.session)
                .equatable()
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
    /// Since when the agent has shown nothing new (`SessionState.quietSince`).
    let quietSince: Date?

    var body: some View {
        HStack(spacing: DS.Space.md) {
            DotGridLoader(pattern: .typing)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            if let quietSince {
                QuietThinkingLabel(since: quietSince)
            } else {
                Text("Working…")
            }
        }
        .font(.dsCallout)
        .foregroundStyle(.dsTextSecondary)
    }
}

/// "Thinking 12s…" once the agent has been quiet for three seconds. Most agents think without
/// streaming their reasoning (or send its summary only at the end), so a count is the only sign
/// the turn hasn't stalled. Sooner than that, it's "Working…".
private struct QuietThinkingLabel: View {
    let since: Date

    var body: some View {
        let clock = DSSecondClock.shared
        Group {
            if clock.now.timeIntervalSince(since) >= 3 {
                HStack(spacing: 0) {
                    Text("Thinking ")
                    ElapsedTimeText(since: since)
                    Text(verbatim: "…")
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Working…")
            }
        }
        .task { await clock.hold() }
    }
}
