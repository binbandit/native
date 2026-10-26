#if DEBUG
import Experiments
import SwiftUI

struct DiffCommentsPreviewHost<Content: View>: View {
    let content: (SessionModel) -> Content
    private let experiments: ExperimentStore
    @State private var app: AppModel
    @State private var session: SessionModel?

    init(_ state: String = "C5", @ViewBuilder content: @escaping (SessionModel) -> Content) {
        experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(true, for: .composerNext)
        let app = AppModel.preview(.empty)
        _app = State(initialValue: app)
        _session = State(initialValue: DiffCommentsPreviewFixtures.session(state, in: app))
        self.content = content
    }

    var body: some View {
        if let session {
            content(session).environment(\.experimentStore, experiments).environment(app).environment(
                BuiltInPlugins.automation.center
            )
            .environment(\.diffCommentsSession, session)
        }
    }
}
#endif
