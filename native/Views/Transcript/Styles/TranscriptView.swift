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

    var body: some View {
        let items = session.state.items
        let rows = unfoldsExploration ? items.map(TranscriptRow.item) : TranscriptRow.rows(from: items)
        let transcript = TranscriptStyleConfiguration(
            session: session, rows: rows, openSubagent: openSubagent,
            sessionTitle: { model.session(id: $0)?.displayTitle }
        )
        ScrollView {
            AnyView(style.makeBody(transcript))
                // Invariant: the rows' height must never depend on whether the vertical scroller is
                // showing. Legacy (mouse) scrollers take layout width, and they appear whenever the
                // content overflows, even for one pass. If the column followed the content width,
                // a scroller flash would rewrap and re-estimate the lazy rows, the new height could
                // hide the scroller again, and the two states fed each other forever: a 100% CPU
                // hang on the main thread. So the column is sized from the scroll container, which
                // a scroller doesn't change.
                .containerRelativeFrame(.horizontal) { containerWidth, _ in
                    max(min(columnWidth, containerWidth - 2 * DS.Space.xxl), 0)
                }
                .padding(.top, DS.Space.xl)
                .padding(.bottom, DS.Space.lg)
                .frame(maxWidth: .infinity)
        }
        // Start at the latest message and stay there as rows grow. Short transcripts sit at the top,
        // as in the reference app: bottom-aligning them (the `.alignment` role) pads the top by an inset that
        // lags the content height by one pass, so every new row briefly overflows and flashes a
        // legacy scroller.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
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
}
