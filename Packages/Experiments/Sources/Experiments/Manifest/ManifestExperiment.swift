import Foundation
/// An experiment as a plugin's `plugin.json` declares it (docs/plugins.md, Experiments). A data-only
/// plugin has no code to read it, so a gate switches the contributions marked with its id, and a
/// parameter fills `${experiment:<id>}` placeholders in its agents' and MCP servers' settings.
public struct ManifestExperiment: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case gate, parameter
    }

    public struct Option: Codable, Hashable, Sendable {
        public var value: StoredValue
        public var title: String?
    }

    /// Whole numbers from `min` to `max`, `step` apart.
    public struct Range: Codable, Hashable, Sendable {
        public var min: Int
        public var max: Int
        public var step: Int?
    }

    /// Any text the user types.
    public struct Text: Codable, Hashable, Sendable {
        public var placeholder: String?
    }

    /// Unique within the plugin. Native prefixes it with the plugin's id (`acme.fast-mode`).
    public var id: String
    public var kind: Kind
    public var title: String
    public var summary: String
    /// "labs" (the default) or "beta".
    public var stage: String?
    /// Defaults to the plugin's name.
    public var owner: String?
    /// `YYYY-MM-DD`.
    public var reviewBy: String
    public var requiresRelaunch: Bool?
    public var defaultValue: StoredValue?
    /// A parameter's values: exactly one of these.
    public var options: [Option]?
    public var range: Range?
    public var text: Text?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, stage, owner, reviewBy, requiresRelaunch, options, range, text
        case defaultValue = "default"
    }

    /// The experiment Labs offers, or what's wrong with it. `uses` are the places it changes.
    func descriptor(
        plugin: String, pluginName: String, uses: [String]
    ) throws(ManifestExperimentProblem) -> ExperimentDescriptor {
        func problem(_ message: String) -> ManifestExperimentProblem {
            ManifestExperimentProblem(experiment: id, message: message)
        }
        guard !id.isEmpty, id.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }) else {
            throw problem("Its id should be lowercase words joined with hyphens.")
        }
        guard let reviewBy = ReviewDate(iso: reviewBy) else {
            throw problem("\"reviewBy\" should be a date like 2027-01-31.")
        }
        let stage: ExperimentStage
        switch self.stage {
        case nil, "labs": stage = .labs
        case "beta": stage = .beta
        case let other?: throw problem("\"stage\" should be \"labs\" or \"beta\", not \"\(other)\".")
        }
        let site = uses.isEmpty ? "Nothing in the plugin yet" : uses.formatted(.list(type: .and))
        let tier: ExperimentDescriptor.Tier
        switch kind {
        case .gate:
            guard options == nil, range == nil, text == nil else {
                throw problem("A gate is on or off; \"options\", \"range\" and \"text\" are for parameters.")
            }
            guard case .bool(let isOn) = defaultValue ?? .bool(false) else {
                throw problem("A gate's \"default\" should be true or false.")
            }
            tier = .gate(defaultValue: isOn, site: site)
        case .parameter:
            let input = try parameterInput()
            guard let defaultValue else { throw problem("A parameter needs a \"default\".") }
            let spec = ParameterSpec(defaultValue: defaultValue, input: input, site: site)
            guard spec.accepts(defaultValue) else {
                throw problem("Its \"default\", \(defaultValue.text), isn't one of its values.")
            }
            tier = .parameter(spec)
        }
        return ExperimentDescriptor(
            id: ExperimentID(namespace: plugin, id), title: title, summary: summary, stage: stage,
            owner: owner ?? pluginName, reviewBy: reviewBy, requiresRelaunch: requiresRelaunch ?? false, tier: tier
        )
        .contributed(byPlugin: plugin, named: pluginName)
    }

    private func parameterInput() throws(ManifestExperimentProblem) -> ParameterSpec.Input {
        func problem(_ message: String) -> ManifestExperimentProblem {
            ManifestExperimentProblem(experiment: id, message: message)
        }
        switch (options, range, text) {
        case (let options?, nil, nil):
            guard !options.isEmpty else { throw problem("\"options\" is empty.") }
            guard Set(options.map(\.value.kind)).count == 1 else {
                throw problem("Its options should all be text, or all be numbers.")
            }
            guard Set(options.map(\.value)).count == options.count else {
                throw problem("Two of its options have the same value.")
            }
            return .options(options.map { ParameterSpec.Option(value: $0.value, title: $0.title ?? $0.value.text) })
        case (nil, let range?, nil):
            let step = range.step ?? 1
            guard range.min <= range.max, step > 0 else {
                throw problem("\"range\" needs \"min\" at most \"max\", and a positive \"step\".")
            }
            let values = Array(stride(from: range.min, through: range.max, by: step))
            guard values.count <= 200 else { throw problem("\"range\" has more than 200 values.") }
            return .options(values.map { ParameterSpec.Option(value: .int($0), title: String($0)) })
        case (nil, nil, let text?):
            return .text(placeholder: text.placeholder ?? "")
        default:
            throw problem("A parameter needs exactly one of \"options\", \"range\" or \"text\".")
        }
    }
}

/// Why one of a plugin's experiments isn't offered, or one of its contributions refers to an
/// experiment that isn't there.
public struct ManifestExperimentProblem: Error, Hashable, Sendable {
    /// The experiment's id as the manifest writes it, when known.
    public let experiment: String?
    public let message: String

    public init(experiment: String?, message: String) {
        self.experiment = experiment
        self.message = message
    }
}
