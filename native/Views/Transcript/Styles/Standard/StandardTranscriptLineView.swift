import ACP
import SwiftUI

/// What the standard transcript's lines share: the session they show and the transcript's own state.
/// None of a line's views read the session's state, which changes with every streamed chunk; what a
/// line needs from it is in the line (`StandardTranscriptLine.plan`) or here.
struct StandardTranscriptLineContext {
    let transcript: TranscriptStyleConfiguration
    /// The line a search result opened at, highlighted for a moment.
    let revealedLine: StandardTranscriptLine.ID?
    /// Earlier turns the user opened back up.
    let unfoldedTurns: Binding<Set<TranscriptTurn.ID>>

    /// Whether lines drawn with `self` look the same drawn with `other`.
    func drawsLike(_ other: Self) -> Bool {
        transcript.session === other.transcript.session && transcript.shortcutTarget == other.transcript.shortcutTarget
            && revealedLine == other.revealedLine
    }
}

/// A run of the standard transcript's lines, one view each, that only updates when its list's
/// version or the context it draws with moves: the earlier turns' lines, while a reply streams into
/// the latest turn. SwiftUI compares a view like this one (Equatable, and not plain data) with `==`.
struct StandardTranscriptLines: View, Equatable {
    let list: StandardTranscriptLineList
    let context: StandardTranscriptLineContext

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.list.version == rhs.list.version && lhs.context.drawsLike(rhs.context)
    }

    var body: some View {
        ForEach(list.lines) { line in
            StandardTranscriptLineView(line: line, context: context)
        }
    }
}

/// One line of the standard transcript, as one view whatever it holds: a lazy stack walks every
/// line of a ForEach whose rows can be zero or several views, on every layout pass.
struct StandardTranscriptLineView: View {
    let line: StandardTranscriptLine
    let context: StandardTranscriptLineContext

    private var transcript: TranscriptStyleConfiguration {
        context.transcript
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background {
            if line.id == context.revealedLine {
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(Color.dsAccentSubtle)
                    .padding(-DS.Space.sm)
                    .transition(.opacity)
            }
        }
        .padding(.top, line.spacing)
        // Outermost, so its frame is the one `scrollTo` lines up.
        .sessionTranscriptLine(line.id)
    }

    @ViewBuilder private var content: some View {
        switch line.kind {
        case .row(let row, _, let thinking):
            self.row(row, thinking: thinking)
        case .replySection(let source, let isFirst, _):
            MarkdownSectionView(source: source, isFirst: isFirst)
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .artifacts(let attachments, _):
            MessageAttachmentsView(attachments: attachments, alignment: .leading)
        case .activityRun(let run):
            ToolRunView(run: run, session: transcript.session)
                .equatable()
        case .fold(let turn, let summary, let isUnfolded):
            TurnActivityFold(summary: summary, isUnfolded: isUnfolded) {
                withAnimation(.reveal) {
                    if isUnfolded {
                        context.unfoldedTurns.wrappedValue.remove(turn.id)
                    } else {
                        context.unfoldedTurns.wrappedValue.insert(turn.id)
                    }
                }
            }
        case .footer(let turn, let summary, let ending, let showsChanges, let subagents):
            TurnFooter(
                turn: turn, summary: summary, ending: ending, showsChanges: showsChanges,
                subagents: subagents, openSubagent: transcript.openSubagent)
        case .changes(let summary):
            TurnChangesCard(summary: summary)
        case .usageLimit(let stop, let isLatestTurn):
            UsageLimitTranscriptCard(session: transcript.session, stop: stop, isLatestTurn: isLatestTurn)
        }
    }

    @ViewBuilder private func row(_ row: TranscriptRow, thinking: ThinkingClock?) -> some View {
        switch row {
        case .exploration(let calls):
            transcript.exploration(calls)
        case .item(.message(let message)):
            MessageView(message: message, thinking: thinking)
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
}

#if DEBUG
#Preview("Standard transcript - Artifacts") {
    DSPreviewPair {
        MessageAttachmentsView(
            attachments: [
                MessageAttachment(name: "Diagram.png", url: nil, imageData: ArtifactPreviewFixtures.imageData)
            ], alignment: .leading
        )
        .environment(\.openTranscriptArtifact, TranscriptArtifactOpener(session: nil, filesAreLocal: true))
        .frame(width: 480)
    }
}
#endif
