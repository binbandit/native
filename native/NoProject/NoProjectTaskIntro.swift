import SwiftUI

struct NoProjectTaskIntro: View {
    let session: SessionModel

    var body: some View {
        EmptyStateView(
            "What would you like to do?", systemImage: "text.bubble",
            message:
                "Ask a question, draft something, or explore an idea. Your files stay private until you move this task to a project."
        ) {
            Button("Write a Message") { session.wantsComposerFocus = true }
        }
    }
}

#if DEBUG
#Preview("No project - Empty task") {
    let app = AppModel.preview(.empty)
    DSPreviewPair {
        if let session = SessionModel.preview(in: app) {
            NoProjectTaskIntro(session: session).frame(width: 800, height: 500)
        }
    }
    .environment(app)
}
#endif
