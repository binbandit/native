#if DEBUG
import Experiments

/// Constructed once after the fixture mounts, so view comparison never creates another app model.
@MainActor
final class DiffCommentsFixtureModel {
    let app: AppModel
    let session: SessionModel?
    let experiments: ExperimentStore

    init(_ state: String, populated: Bool = true) {
        experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(true, for: .composerNext)
        app = AppModel.preview(populated ? .populated : .empty)
        session = DiffCommentsPreviewFixtures.session(state, in: app)
    }
}
#endif
