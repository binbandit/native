/// A data-only plugin's experiments, checked: the ones Labs can offer, and a problem for each one
/// that it can't, or for each place that refers to an experiment that isn't there. One bad
/// experiment never takes the plugin or its other experiments down with it.
public struct PluginExperiments: Sendable {
    /// A place in the plugin that an experiment changes.
    public struct Use: Hashable, Sendable {
        public enum Role: Hashable, Sendable {
            /// A contribution marked `"experiment": "<id>"`, there only while that gate is on.
            case switches
            /// A setting with a `${experiment:<id>}` placeholder.
            case fills
        }

        public let experiment: String
        public let role: Role
        /// As Labs names it: `workflow “Fast review”`.
        public let place: String

        public init(experiment: String, role: Role, place: String) {
            self.experiment = experiment
            self.role = role
            self.place = place
        }
    }

    public private(set) var descriptors: [ExperimentDescriptor] = []
    public private(set) var problems: [ManifestExperimentProblem] = []

    /// - Parameter reserved: Ids already taken, by Native or by plugins checked before this one.
    public init(
        plugin: String, name: String, declared: ManifestExperimentList, uses: [Use], reserved: Set<ExperimentID>
    ) {
        problems = declared.malformed
        var seen: Set<String> = []
        var kinds: [String: ManifestExperiment.Kind] = [:]
        for experiment in declared.valid {
            guard seen.insert(experiment.id).inserted else {
                problems.append(.init(experiment: experiment.id, message: "It's declared twice; the first is used."))
                continue
            }
            let id = ExperimentID(namespace: plugin, experiment.id)
            guard !reserved.contains(id) else {
                problems.append(.init(experiment: experiment.id, message: "\(id) is already used by another experiment."))
                continue
            }
            let places = uses.filter { $0.experiment == experiment.id }.map(\.place)
            do {
                descriptors.append(try experiment.descriptor(plugin: plugin, pluginName: name, uses: places))
                kinds[experiment.id] = experiment.kind
            } catch {
                problems.append(error)
            }
        }
        for use in uses where !seen.contains(use.experiment) {
            problems.append(
                .init(experiment: use.experiment, message: "\(use.place) refers to it, but plugin.json doesn't declare it.")
            )
        }
        for use in uses where use.role == .switches && kinds[use.experiment] == .parameter {
            problems.append(
                .init(experiment: use.experiment, message: "\(use.place) is switched by it, but only gates switch things.")
            )
        }
    }
}
