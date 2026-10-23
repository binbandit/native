#if DEBUG
import SwiftUI

struct HomeNextFixtureView: View {
    @State private var model: AppModel?
    let state: HomeNextPreviewFixtures.State

    var body: some View {
        Group {
            if let model {
                HomeNextView(agents: HomeNextPreviewFixtures.agents, isLoading: state == .loading).environment(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Creating a preview registry updates the experiment catalog. Do it once after layout,
            // never in init: a gate's redraw would otherwise create another registry indefinitely.
            guard model == nil else { return }
            model = HomeNextPreviewFixtures.model(state)
        }
    }
}

#Preview("Next fixture - First launch") { HomeNextPreviewFixtures.page(.first) }
#endif
