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
    @State private var position = ScrollPosition()
    /// Whether the newest output is out of view.
    @State private var isAwayFromLatest = false
    /// The scroll container's width, which a legacy scroller doesn't change.
    @State private var containerWidth: CGFloat?

    var body: some View {
        let items = session.state.items
        let rows = unfoldsExploration ? items.map(TranscriptRow.item) : TranscriptRow.rows(from: items)
        let transcript = TranscriptStyleConfiguration(
            session: session, rows: rows, openSubagent: openSubagent,
            sessionTitle: { model.session(id: $0)?.displayTitle }
        )
        ScrollView {
            column(transcript)
        }
        // Start at the latest message and stay there as rows grow. Short transcripts sit at the top,
        // as in Factory: bottom-aligning them (the `.alignment` role) pads the top by an inset that
        // lags the content height by one pass, so every new row briefly overflows and flashes a
        // legacy scroller.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.width
        } action: { _, width in
            containerWidth = width
        }
        .onScrollGeometryChange(for: String.self) { g in
            "content \(g.contentSize.height) container \(g.containerSize.height) offset \(g.contentOffset.y) insets \(g.contentInsets.top),\(g.contentInsets.bottom) visible \(g.visibleRect.minY)-\(g.visibleRect.maxY)"
        } action: { _, new in
            if let h = FileHandle(forWritingAtPath: "/tmp/stabilize-tools/geo.log") { h.seekToEndOfFile(); h.write(Data("STABDBG \(Date().timeIntervalSince1970) \(new)\n".utf8)); try? h.close() }
        }
        .onScrollGeometryChange(for: Bool.self) { [threshold = DS.Space.xxxl] geometry in
            geometry.visibleRect.maxY < geometry.contentSize.height - threshold
        } action: { _, isAway in
            isAwayFromLatest = isAway
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
                ProgressView("Loading session…")
            } else if items.isEmpty {
                ContentUnavailableView(
                    "What should we work on?", systemImage: "sparkles", description: Text(session.cwd.abbreviatedPath)
                )
            }
        }
    }

    /// The rows in a centered column, as wide as the width setting allows with a margin each side.
    private func column(_ transcript: TranscriptStyleConfiguration) -> some View {
        AnyView(style.makeBody(transcript))
            .frame(maxWidth: maxColumnWidth)
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
    private var maxColumnWidth: CGFloat {
        guard let containerWidth else { return columnWidth }
        return max(min(columnWidth, containerWidth - 2 * DS.Space.xxl), 0)
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
