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
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "HANG_noAnchor") ? nil : .bottom)
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "HANG_noSizeAnchor") || UserDefaults.standard.bool(forKey: "HANG_noAnchor") ? nil : .bottom, for: .sizeChanges)
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
