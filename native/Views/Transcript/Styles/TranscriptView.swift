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

    var body: some View {
        let items = session.state.items
        let rows = unfoldsExploration ? items.map(TranscriptRow.item) : TranscriptRow.rows(from: items)
        let transcript = TranscriptStyleConfiguration(session: session, rows: rows, openSubagent: openSubagent)
        ScrollView {
            AnyView(style.makeBody(transcript))
                .frame(maxWidth: columnWidth)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
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
