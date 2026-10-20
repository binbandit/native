#if NATIVE_PREVIEWS_WIP
import Experiments
import Foundation

/// Labs previews' data: Native's own experiments, kept in memory.
enum LabsPreviewFixtures {
    static func store() -> ExperimentStore {
        ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
    }

    /// The first two experiments both claiming one extension point, as a conflict reports it.
    static let conflict: ExtensionConflict? = {
        let experiments = ExperimentCatalog.native.experiments.prefix(2).map(\.id)
        let point = ExtensionPoint(id: "transcript.style", title: "Transcript style", default: "standard")
        let resolver = ExtensionResolver(
            contributions: experiments.map { Contribution(source: .experiment($0), claim: Claim(point, $0.rawValue)) })
        guard case .conflict(let conflict) = resolver.outcome(for: point.id) else { return nil }
        return conflict
    }()

    static let problem = PluginExperimentProblem(
        pluginID: "acme-themes", pluginName: "Acme Themes",
        problem: ManifestExperimentProblem(
            experiment: "acme.compact-rows", message: "“default” must be one of the choices it lists"))
}
#endif
