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
    @State private var position = ScrollPosition(edge: .bottom)
    /// Whether the newest output is out of view.
    @State private var isAwayFromLatest = false
    /// The scroll container's width, which a legacy scroller doesn't change; nil until the container
    /// has a real size.
    @State private var containerWidth: CGFloat?
    /// Rows the user opened, kept while they're scrolled away.
    @State private var disclosures = TranscriptDisclosures()

    var body: some View {
        let items = session.state.items
        let rows = unfoldsExploration ? items.map(TranscriptRow.item) : TranscriptRow.rows(from: items)
        let transcript = TranscriptStyleConfiguration(
            session: session, rows: rows, openSubagent: openSubagent,
            sessionTitle: { model.session(id: $0)?.displayTitle }
        )
        // Sized by the space it's given, never by its rows. The window works out its minimum size by
        // laying out its content at no width, on every update; a transcript laid out that narrow
        // (each line of text wrapped a character at a time) took most of the main thread while a
        // reply streamed. An overlay is laid out only at its base's final size.
        Color.clear.overlay {
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
            // session's title; the hard edge keeps the title on a plain backing.
            .scrollEdgeEffectStyle(.hard, for: .top)
            // The scroll view's own size, reported from the first layout on (scroll geometry only
            // reports changes, and a session switched to is laid out at its final size from the start).
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                // A view that's just been made (a session reopened, or back from Settings) is first laid
                // out at a sliver with no height or no width. Rows measured that narrow come out
                // thousands of points tall, and the lazy stack keeps them as its estimates, so the
                // transcript opened mid-way or past its end, blank. The rows wait for a real size.
                guard size.width > 0, size.height > 0 else { return }
                containerWidth = size.width
            }
            .onScrollGeometryChange(for: Bool.self) { [threshold = DS.Space.xxxl] geometry in
                geometry.visibleRect.maxY < geometry.contentSize.height - threshold
            } action: { _, isAway in
                isAwayFromLatest = isAway
            }
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
            if session.phase == .loading {
                LoadingStateView("Loading session…")
            } else if items.isEmpty {
                ContentUnavailableView(
                    "What should we work on?", systemImage: "sparkles", description: Text(session.cwd.abbreviatedPath)
                )
            }
        }
    }

    /// The rows in a centered column, as wide as the width setting allows with a margin each side.
    private func column(_ transcript: TranscriptStyleConfiguration, in containerWidth: CGFloat) -> some View {
        AnyView(style.makeBody(transcript))
            .environment(disclosures)
            .frame(maxWidth: maxColumnWidth(in: containerWidth))
            .padding(.top, DS.Space.xl)
            .padding(.bottom, DS.Space.lg)
            .frame(maxWidth: .infinity)
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
