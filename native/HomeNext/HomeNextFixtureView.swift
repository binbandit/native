#if DEBUG
import SwiftUI

struct HomeNextFixtureView: View {
    @State private var model: AppModel
    let state: HomeNextPreviewFixtures.State

    init(state: HomeNextPreviewFixtures.State) {
        self.state = state
        _model = State(initialValue: HomeNextPreviewFixtures.model(state))
    }

    var body: some View {
        HomeNextView(agents: HomeNextPreviewFixtures.agents, isLoading: state == .loading).environment(model)
    }
}

#Preview("Next fixture - First launch") { HomeNextPreviewFixtures.page(.first) }
#endif
