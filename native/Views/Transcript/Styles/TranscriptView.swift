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
        .focusedSceneValue(\.transcriptJumpToLatest, isPrimary && isAwayFromLatest ? { jumpToLatest() } : nil)
        .onScrollGeometryChange(for: String.self) { g in
            "content \(g.contentSize) insets \(g.contentInsets) container \(g.containerSize) offset \(g.contentOffset)"
        } action: { _, new in
            FileHandle.standardError.write(Data("HANG \(Date().timeIntervalSince1970) \(new)\n".utf8))
        }
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

    /// The rows in a centered column: as wide as the width setting allows, with a margin each side.
    private func column(_ transcript: TranscriptStyleConfiguration) -> some View {
        let maxWidth = columnWidth
        let margin = DS.Space.xxl
        return AnyView(style.makeBody(transcript))
            // Invariant: the rows' height must never depend on whether the vertical scroller is
            // showing. Legacy (mouse) scrollers take layout width, and they appear whenever the
            // content overflows, even for one pass. If the column followed the content width, a
            // scroller flash would rewrap and re-estimate the lazy rows, the new height could hide
            // the scroller again, and the two states fed each other forever: a 100% CPU hang on the
            // main thread. So the column is sized from the scroll container, which a scroller
            // doesn't change.
            .containerRelativeFrame(.horizontal) { containerWidth, _ in
                max(min(maxWidth, containerWidth - 2 * margin), 0)
            }
            .padding(.top, DS.Space.xl)
            .padding(.bottom, DS.Space.lg)
            .frame(maxWidth: .infinity)
    }

    /// Only while a turn runs: afterwards the latest is the turn's end, and scrolling up is reading.
    private var showsJumpToLatest: Bool {
        isAwayFromLatest && session.phase == .prompting
    }

    private func jumpToLatest() {
        withAnimation(.dsStandard) { position.scrollTo(edge: .bottom) }
    }
}
