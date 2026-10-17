import ACP
import SwiftUI

struct SessionView: View {
    let session: SessionModel
    /// The subagent whose conversation is open in the inspector.
    @State private var openSubagent: SessionID?
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth

    var body: some View {
        TranscriptView(session: session) { openSubagent = $0 }
            // A bar rather than an inset, so the transcript gets the system scroll edge effect under it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                ComposerView(session: session)
            }
            .focusedSceneValue(\.activeSession, session)
            .navigationTitle(session.displayTitle)
            .navigationSubtitle(session.cwd.abbreviatedPath)
            .inspector(isPresented: Binding(get: { openSubagent != nil }, set: { if !$0 { openSubagent = nil } })) {
                if let id = openSubagent, let subagent = session.state.subagents.first(where: { $0.id == id }) {
                    SubagentInspector(subagent: subagent, child: session.child(id))
                        .inspectorColumnWidth(min: 340, ideal: 420, max: 640)
                }
            }
            .environment(\.transcriptColumnMaxWidth, columnWidth.maxWidth)
    }
}
