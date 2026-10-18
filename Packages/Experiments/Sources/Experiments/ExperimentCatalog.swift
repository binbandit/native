/// Every experiment an app offers, in the order Labs lists them.
public struct ExperimentCatalog: Sendable {
    /// Experiments declared by one source, for Labs to list together.
    public struct Group: Identifiable, Sendable {
        public let origin: ExperimentOrigin
        public let experiments: [ExperimentDescriptor]

        public var id: String {
            switch origin {
            case .native: "native"
            case .plugin(let id, _): "plugin.\(id)"
            }
        }
    }

    public let experiments: [ExperimentDescriptor]

    public init(_ declarations: [any ExperimentDeclaration]) {
        let descriptors = declarations.map(\.descriptor)
        assert(Set(descriptors.map(\.id)).count == descriptors.count, "An experiment is declared twice")
        self.init(descriptors: descriptors)
    }

    /// Keeps the first experiment with each id; callers check for clashes before (plugins report
    /// theirs as problems).
    public init(descriptors: [ExperimentDescriptor]) {
        var seen: Set<ExperimentID> = []
        experiments = descriptors.filter { seen.insert($0.id).inserted }
    }

    public func descriptor(for id: ExperimentID) -> ExperimentDescriptor? {
        experiments.first { $0.id == id }
    }

    /// Native's experiments, then each plugin's, in catalog order.
    public var groups: [Group] {
        var order: [ExperimentOrigin] = []
        var members: [ExperimentOrigin: [ExperimentDescriptor]] = [:]
        for experiment in experiments {
            if members[experiment.origin] == nil {
                order.append(experiment.origin)
            }
            members[experiment.origin, default: []].append(experiment)
        }
        return order.map { Group(origin: $0, experiments: members[$0] ?? []) }
    }
}
