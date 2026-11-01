import SwiftUI

/// What the agents before a session did, at the top of its transcript, loaded when it appears. Until
/// it loads, or when there's nothing to show, the transcript is as before.
struct TaskHistoryPrelude: View {
    let session: SessionModel
    var contexts = TaskHistoryContexts.shared

    var body: some View {
        VStack(spacing: 0) {
            if case .shown(let context) = contexts.context(for: session) {
                TaskHistoryContextView(context: context)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.dsStandard, value: contexts.context(for: session))
        .task(id: session.host?.id) { await contexts.load(session) }
    }
}
