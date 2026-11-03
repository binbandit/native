import ACP
import SwiftUI

/// What the other agents did while a returning conversation was away, as a collapsed row above the
/// context marker where it came back, loaded when the marker appears. Until it loads, or when
/// there's nothing to show, the marker shows alone.
struct TaskHistoryMarkerContent: View {
    let session: SessionModel
    let marker: PromptPreamble.Marker
    var contexts = TaskHistoryContexts.shared

    private struct Reload: Hashable {
        let marker: String
        let isRestoring: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .shown(let context) = contexts.context(for: session, marker: marker.id) {
                TaskHistoryCatchUp(context: context)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.dsStandard, value: contexts.context(for: session, marker: marker.id))
        // Again after a reload, whose replay can keep different markers above this one.
        .task(id: Reload(marker: marker.id, isRestoring: session.isRestoringHistory)) {
            guard !session.isRestoringHistory else { return }
            await contexts.load(session, marker: marker.id)
        }
    }
}
