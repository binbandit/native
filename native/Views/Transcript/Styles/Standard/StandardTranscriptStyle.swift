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
    /// Each turn's lines, kept until the turn changes.
    @State private var lineCache = StandardTranscriptLineCache()
    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?

    var body: some View {
        let plan = StandardTranscriptLine.plan(
            transcript, folding: foldsEarlierTurns, unfolded: unfoldedTurns, cache: lineCache)
        let context = StandardTranscriptLineContext(
            transcript: transcript, revealedLine: revealedLine, unfoldedTurns: $unfoldedTurns)
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                // Earlier turns as a list of their own, which a chunk streaming into the latest
                // turn leaves alone. Equatable by its own conformance, not `.equatable()`: that view
                // is a single view, so the lazy stack would build every earlier line at once.
                StandardTranscriptLines(list: plan.earlier, context: context)
                ForEach(plan.latest) { line in
                    StandardTranscriptLineView(line: line, context: context)
                }
                if transcript.isWorking {
                    WorkingIndicator(
                        status: transcript.session.taskStatus, quietSince: transcript.session.state.quietSince
                    )
                    .padding(.top, DS.Space.xl)
                }
            }
            #if DEBUG || NATIVE_PERF
            .task { await TranscriptAutoScroll.runIfRequested(session: transcript.session, proxy: proxy) }
            #endif
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
        let lines = StandardTranscriptLine.plan(
            transcript, folding: foldsEarlierTurns, unfolded: unfoldedTurns, cache: lineCache
        ).lines
        let line = lines.first { line in
            switch line.kind {
            case .row(let row, let start, _): (start..<start + row.itemCount).contains(index)
            case .replySection(_, _, let start): start == index
            case .activityRun(let run): run.transcriptIndices.contains(index)
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
    /// The task's status as every surface reads it (`SessionModel.taskStatus`).
    let status: TaskStatus
    /// Since when the agent has shown nothing new (`SessionState.quietSince`).
    let quietSince: Date?

    var body: some View {
        HStack(spacing: DS.Space.md) {
            if status.needsAttention {
                // The turn is the user's move, not the agent's: say what it waits for, in the words
                // the sidebar and the status bar use, rather than count thinking that isn't happening.
                StatusIndicator(status: status, size: DS.Size.statusGlyph)
                Text(status.label)
            } else {
                DotGridLoader(pattern: .typing)
                    .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                if let quietSince {
                    QuietThinkingLabel(since: quietSince)
                } else {
                    Text("Working…")
                }
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
