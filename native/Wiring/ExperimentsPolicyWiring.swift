import Experiments
import Observation

/// Holds every experiment at its default while the organization turns Labs off
/// (`policy.labs.enabled`), without forgetting what the user chose there. Connected once at launch,
/// before anything reads an experiment.
@MainActor
enum ExperimentsPolicyWiring {
    static func connect(policy: PolicyCenter = .shared, experiments: ExperimentStore = .shared) {
        experiments.isFrozen = !policy.policy.labsEnabled
        Task {
            for await labsEnabled in Observations({ policy.policy.labsEnabled }) {
                experiments.isFrozen = !labsEnabled
            }
        }
    }
}
