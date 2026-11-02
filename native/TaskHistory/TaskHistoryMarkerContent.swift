import ACP
import SwiftUI

/// What the other agents did while a returning conversation was away, above the context marker
/// where it came back, loaded when the marker appears. Until it loads, or when there's nothing to
/// show, the marker shows alone.
struct TaskHistoryMarkerContent: View {
    let session: SessionModel
    let marker: PromptPreamble.Marker
    var contexts = TaskHistoryContexts.shared

    var body: some View {
        VStack(spacing: 0) {
            if case .shown(let context) = contexts.context(for: session, marker: marker.id) {
                TaskHistoryContextView(context: context)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.dsStandard, value: contexts.context(for: session, marker: marker.id))
        .task(id: marker.id) { await contexts.load(session, marker: marker.id) }
    }
}
