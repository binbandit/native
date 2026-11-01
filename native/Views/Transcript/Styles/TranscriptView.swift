import ACP
import SwiftUI

/// A session's conversation. Also shows a subagent's conversation in the inspector.
///
/// Scrolling and the loading and empty states are the same for every style; the rows come from the
/// transcript style in effect (`.transcriptStyle`).
struct TranscriptView: View {
    let session: SessionModel
    let openSubagent: (SessionID) -> Void

    @Resolved(.transcriptStyle) private var style: any TranscriptStyle
    @Experiment(.unfoldExploration) private var unfoldsExploration
    @Environment(\.transcriptColumnMaxWidth) private var columnWidth
    @Environment(AppModel.self) private var model
    @Environment(\.isPrimaryTranscript) private var isPrimary
    @Environment(\.dsDrawsToolbarBand) private var drawsToolbarBand
    @Environment(\.transcriptTrailer) private var trailer
    @State private var position = ScrollPosition(edge: .bottom)
    /// Whether the newest output is out of view.
    @State private var isAwayFromLatest = false
    /// The scroll container's width, which a legacy scroller doesn't change; nil until the container
    /// has a real size.
    @State private var containerWidth: CGFloat?
    @State private var containerHeight: CGFloat?
    /// The code the transcript shows first has its colors (`TranscriptOpeningCode`), or it stopped
    /// waiting for them. Until then the rows wait, so the transcript appears finished.
    @State private var isOpeningCodeColored = false
    /// Whether the loading state stays while the code colors: after history was restored here, so
    /// "Loading session…" stays until the transcript appears. A session already in memory shows
    /// nothing for those few milliseconds instead of flashing a loader.
    @State private var loadsWhileColoring: Bool

    init(session: SessionModel, openSubagent: @escaping (SessionID) -> Void) {
        self.session = session
        self.openSubagent = openSubagent
        _loadsWhileColoring = State(initialValue: session.isRestoringHistory)
    }

    var body: some View {
        let transcript = TranscriptStyleConfiguration(
            session: session, unfoldsExploration: unfoldsExploration, openSubagent: openSubagent,
            sessionTitle: { model.session(id: $0)?.displayTitle }
        )
        // Sized by the space it's given, never by its rows. The window works out its minimum size by
        // laying out its content at no width, on every update; a transcript laid out that narrow
        // (each line of text wrapped a character at a time) took most of the main thread while a
        // reply streamed. An overlay is laid out only at its base's final size.
        Color.clear
            // The space the transcript gets, reported from the first layout on (geometry changes
            // aren't reported for a size a view starts with), so the scroll view lays its rows out at
            // their width in its first pass.
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                // A view that's just been made (a session reopened, or back from Settings) is first laid
                // out at a sliver with no height or no width. Rows measured that narrow come out
                // thousands of points tall, and the lazy stack keeps them as its estimates, so the
                // transcript opened mid-way or past its end, blank. The rows wait for a real size.
                guard size.width > 0, size.height > 0 else { return }
                containerWidth = size.width
                containerHeight = size.height
            }
            .overlay {
                let showsRows = !session.isRestoringHistory && (isOpeningCodeColored || openingCode.isEmpty)
                if !showsRows, session.isRestoringHistory || loadsWhileColoring {
                    // A reopened session replays its history thousands of updates at a time. Shown as
                    // it arrived, rows appeared and the view chased the end, replaying the session;
                    // instead it appears whole, already at its end, once all of it is in.
                    LoadingStateView("Loading task…")
                } else if showsRows {
                    scrollView(transcript)
                }
            }
            .modifier(ArtifactPresentation(session: session, filesAreLocal: !model.device(of: session.key).isRemote))
            .environment(\.toolWorkspaceRoot, session.cwd.path(percentEncoded: false))
            .transaction(value: session.isRestoringHistory) { $0.animation = nil }
            .onChange(of: session.isRestoringHistory) { _, isRestoring in
                guard isRestoring else { return }
                isOpeningCodeColored = false
                loadsWhileColoring = true
            }
            .task(id: session.isRestoringHistory) {
                guard !session.isRestoringHistory, !isOpeningCodeColored else { return }
                await TranscriptOpeningCode.color(openingCode)
                isOpeningCodeColored = true
            }
            .overlay(alignment: .bottom) {
                if showsJumpToLatest {
                    JumpToLatestButton(action: jumpToLatest)
                        .padding(.bottom, DS.Space.md)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.dsStandard, value: showsJumpToLatest)
            .focusedSceneValue(\.transcriptJumpToLatest, jumpCommand)
            .overlay {
                if !session.isRestoringHistory, session.isTranscriptEmpty, !isAgentContinuation {
                    NewSessionEmptyState(session: session)
                }
            }
    }

    private var isAgentContinuation: Bool {
        model.earlierConversations.conversation(before: session.key).map { $0.agent != session.agent.id } ?? false
    }

    private var disclosures: TranscriptDisclosures {
        session.transcriptDisclosures
    }

    /// The code on the transcript's first screen that has no colors yet. Only looked at until the
    /// transcript appears: it reads the session's state, which changes with every chunk.
    private var openingCode: [TranscriptOpeningCode.Block] {
        guard TranscriptOpeningCode.isEnabled, !isOpeningCodeColored else { return [] }
        // Before the container's first layout, a tall window's worth.
        return TranscriptOpeningCode.uncolored(in: session.state.items, height: containerHeight ?? 1200)
    }

    /// The rows, scrolling, starting at the latest.
    private func scrollView(_ transcript: TranscriptStyleConfiguration) -> some View {
        ScrollView {
            if let containerWidth {
                column(transcript, in: containerWidth)
            } else {
                // Keeps the scroll view full width while the rows wait for its size; empty, it has none.
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
        // Start at the latest message and stay there as rows grow. Short transcripts sit at the top:
        // bottom-aligning them (the `.alignment` role) pads the top by an inset that lags the content
        // height by one pass, so every new row briefly overflows and flashes a legacy scroller.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollPosition($position)
        // Rows scrolled up under the title bar stay legible through the soft edge, right behind the
        // session's title; the hard edge keeps the title on a plain backing. Under a page's or an
        // inspector's `dsToolbarBand`, the band in Native's colors takes its place.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectHidden(drawsToolbarBand, for: .top)
        .onScrollGeometryChange(for: Bool.self) { [threshold = DS.Space.xxxl] geometry in
            geometry.visibleRect.maxY < geometry.contentSize.height - threshold
        } action: { _, isAway in
            isAwayFromLatest = isAway
        }
    }

    private func modelChoiceUndo(_ change: ComposerAgentChange) -> (() -> Void)? {
        guard change.canUndo else { return nil }
        return { change.undo() }
    }

    /// The rows in a centered column, as wide as the width setting allows with a margin each side.
    private func column(_ transcript: TranscriptStyleConfiguration, in containerWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            if let change = session.modelChange, change.stage == .applied || change.stage == .reversed {
                ChangeAgentDivider(
                    agentName: session.agentName,
                    modelName: ComposerSettings(session.configOptions).model?.shortModelName,
                    isReversed: change.stage == .reversed, onUndo: modelChoiceUndo(change))
            } else if let earlier = model.earlierConversations.conversation(before: session.key),
                earlier.agent != session.agent.id
            {
                ChangeAgentDivider(agentName: session.agentName)
            }
            AnyView(style.makeBody(transcript))
            if isPrimary, let trailer {
                trailer.content.padding(.top, DS.Space.lg)
            }
        }
        .environment(disclosures)
        .frame(maxWidth: maxColumnWidth(in: containerWidth))
        .padding(.top, DS.Space.xl)
        .padding(.bottom, DS.Space.lg)
        .frame(maxWidth: .infinity)
        // Coming back to this session shows the same place, or the latest (new rows included)
        // when that's where the user left it.
        .sessionTranscriptPlace(for: transcript.session)
    }

    /// Invariant: the rows' height must never depend on whether the vertical scroller is showing.
    /// Legacy (mouse) scrollers take layout width, and they appear whenever the content overflows,
    /// even for one pass. If the column followed the content width, a scroller flash rewrapped and
    /// re-estimated the lazy rows, the new height could hide the scroller again, and the two states
    /// fed each other forever: a 100% CPU hang on the main thread. So the column's width comes from
    /// the scroll container, which a scroller doesn't change, and its margins are wider than a
    /// scroller. It's a maximum, not a fixed width, so it never holds the window open either.
    private func maxColumnWidth(in containerWidth: CGFloat) -> CGFloat {
        max(min(columnWidth, containerWidth - 2 * DS.Space.xxl), 0)
    }

    /// Only while a turn runs: afterwards the latest is the turn's end, and scrolling up is reading.
    private var showsJumpToLatest: Bool {
        isAwayFromLatest && session.phase == .prompting
    }

    /// View ▸ Jump to Latest, while the session's own transcript has scrolled away from it.
    private var jumpCommand: TranscriptJumpCommand? {
        guard isPrimary, isAwayFromLatest else { return nil }
        return TranscriptJumpCommand(sessionID: session.id, action: jumpToLatest)
    }

    private func jumpToLatest() {
        withAnimation(.dsStandard) { position.scrollTo(edge: .bottom) }
    }
}

#if DEBUG
#Preview("Transcript - Switch away and return") {
    let app = AppModel.preview(.empty)
    let sessions = SessionTranscriptPreviewFixtures.sessions(in: app)
    return DSPreviewPair {
        SessionTranscriptPreview(sessions: sessions)
            .environment(app)
    }
}
#endif
