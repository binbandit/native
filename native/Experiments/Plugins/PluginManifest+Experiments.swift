import AppAppearance
import CodeThemes
import Experiments
import NativeAutomation

extension PluginManifest {
    /// Whether experiments change anything in the manifest.
    var usesExperiments: Bool {
        !experiments.declared.isEmpty || !experimentUses.isEmpty
    }

    /// Everything experiments change: the contributions gates switch, and the settings with
    /// `${experiment:<id>}` placeholders.
    var experimentUses: [PluginExperiments.Use] {
        let switches = experiments.marks.map {
            PluginExperiments.Use(experiment: $0.gate, role: .switches, place: $0.place)
        }
        let agentSettings = agents.map { agent in
            (place: "the agent “\(agent.name)”", texts: agent.args + agent.env.values)
        }
        let serverSettings = mcpServers.map { server in
            (
                place: "the MCP server “\(server.name)”",
                texts: (server.args ?? []) + (server.env ?? [:]).values + (server.headers ?? [:]).values
            )
        }
        let fills = (agentSettings + serverSettings).flatMap { setting in
            Set(setting.texts.flatMap(ExperimentPlaceholder.references(in:))).sorted().map {
                PluginExperiments.Use(experiment: $0, role: .fills, place: setting.place)
            }
        }
        return switches + fills
    }

    /// The manifest as its experiments leave it: a contribution behind a gate that isn't on is gone
    /// (an unknown or broken gate counts as off, since what it guards is experimental), and
    /// placeholders hold their experiment's value (empty when there's none).
    ///
    /// - Parameter value: The value in effect for an experiment, by its id as the manifest writes it.
    func applyingExperiments(_ value: (String) -> StoredValue?) -> PluginManifest {
        let marks = Dictionary(experiments.marks.map { (Key(kind: $0.kind, id: $0.id), $0.gate) }) { first, _ in first }
        func isOn(_ kind: ContributionMark.Kind, _ id: String?) -> Bool {
            guard let id, let gate = marks[Key(kind: kind, id: id)] else { return true }
            return value(gate) == .bool(true)
        }
        func fill(_ text: String) -> String {
            ExperimentPlaceholder.substitute(in: text) { value($0)?.text ?? "" }
        }
        var manifest = self
        manifest.agents = agents.filter { isOn(.agent, $0.id) }.map { agent in
            var agent = agent
            agent.args = agent.args.map(fill)
            agent.env = agent.env.mapValues(fill)
            return agent
        }
        manifest.mcpServers = mcpServers.filter { isOn(.mcpServer, $0.name) }.map { server in
            var server = server
            server.args = server.args?.map(fill)
            server.env = server.env?.mapValues(fill)
            server.headers = server.headers?.mapValues(fill)
            return server
        }
        manifest.workflows = workflows.filter { isOn(.workflow, $0.id) }
        manifest.themes.code = themes.code.filter { isOn(.codeTheme, $0.id) }
        manifest.themes.accents = themes.accents.filter { isOn(.accent, $0.id) }
        manifest.iconSets.valid = iconSets.valid.filter { isOn(.iconSet, $0.rawID) }
        manifest.celebrations.valid = celebrations.valid.filter { isOn(.celebration, $0.rawID) }
        return manifest
    }

    private struct Key: Hashable {
        let kind: ContributionMark.Kind
        let id: String
    }
}

extension ThemeJSON {
    fileprivate var id: String? {
        guard case .object(let members) = self, case .string(let id)? = members["id"] else { return nil }
        return id
    }
}
