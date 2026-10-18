import Experiments

/// The experiments enabled plugins add to Labs, checked against Native's and each other's: code
/// plugins' declarations (ids in the plugin's namespace) and data-only plugins' manifests.
struct PluginExperimentSet {
    private(set) var descriptors: [ExperimentDescriptor] = []
    private(set) var problems: [PluginExperimentProblem] = []

    init(plugins: [any NativePlugin], reserved: Set<ExperimentID>) {
        var reserved = reserved
        for plugin in plugins {
            let manifest = plugin.manifest
            var found: [ExperimentDescriptor] = []
            var problems: [ManifestExperimentProblem] = []
            for declaration in plugin.experiments {
                let id = declaration.descriptor.id
                if !id.isNamespaced(by: manifest.id) {
                    problems.append(.init(experiment: id.rawValue, message: "Its id should start with \"\(manifest.id).\"."))
                } else if reserved.contains(id) || found.contains(where: { $0.id == id }) {
                    problems.append(.init(experiment: id.rawValue, message: "\(id) is already used by another experiment."))
                } else {
                    found.append(declaration.descriptor.contributed(byPlugin: manifest.id, named: manifest.name))
                }
            }
            if manifest.usesExperiments {
                let checked = PluginExperiments(
                    plugin: manifest.id, name: manifest.name, declared: manifest.experiments.declared,
                    uses: manifest.experimentUses, reserved: reserved.union(found.map(\.id))
                )
                found += checked.descriptors
                problems += checked.problems
            }
            reserved.formUnion(found.map(\.id))
            descriptors += found
            self.problems += problems.map {
                PluginExperimentProblem(pluginID: manifest.id, pluginName: manifest.name, problem: $0)
            }
        }
    }
}

/// Something wrong with one of a plugin's experiments, shown in Labs under the plugin's name.
struct PluginExperimentProblem: Hashable, Identifiable {
    let pluginID: String
    let pluginName: String
    let problem: ManifestExperimentProblem

    var id: String { "\(pluginID)/\(problem.experiment ?? "")/\(problem.message)" }
}

extension PluginRegistry.LoadedPlugin {
    /// The plugin as its experiments leave it. Only data-only plugins change; code plugins read
    /// their experiments themselves.
    func applyingExperiments(_ snapshot: ExperimentSnapshot) -> Self {
        guard let manifestPlugin = plugin as? ManifestPlugin, manifestPlugin.manifest.usesExperiments else { return self }
        let manifest = manifestPlugin.manifest
        let applied = manifest.applyingExperiments { snapshot.value(for: ExperimentID(namespace: manifest.id, $0)) }
        return Self(plugin: ManifestPlugin(manifest: applied, policyTranslator: manifestPlugin.policyTranslator), source: source)
    }
}
