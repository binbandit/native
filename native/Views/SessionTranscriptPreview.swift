#if DEBUG
import SwiftUI

/// Switching replaces the transcript just as the session detail does in the main window.
struct SessionTranscriptPreview: View {
    let sessions: [SessionModel]
    @State private var selected = 0
    @State private var memory = SessionTranscriptMemory()

    var body: some View {
        VStack(spacing: DS.Space.md) {
            Picker("Task", selection: $selected) {
                ForEach(sessions.indices, id: \.self) { index in
                    Text(sessions[index].displayTitle).tag(index)
                }
            }
            .pickerStyle(.segmented)
            if sessions.indices.contains(selected) {
                TranscriptView(session: sessions[selected]) { _ in }
                    .id(selected)
            }
        }
        .environment(\.sessionTranscriptMemory, memory)
        .frame(width: 560, height: 640)
    }
}

#Preview("Task transcript - Return visits and empty task") {
    let app = AppModel.preview(.empty)
    let sessions = SessionTranscriptPreviewFixtures.sessions(in: app)
    return DSPreviewPair {
        SessionTranscriptPreview(sessions: sessions)
            .environment(app)
    }
}
#endif
