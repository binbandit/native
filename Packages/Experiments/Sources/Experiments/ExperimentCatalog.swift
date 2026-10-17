/// Every experiment an app offers, in the order Labs lists them.
public struct ExperimentCatalog: Sendable {
    public let experiments: [ExperimentDescriptor]

    public init(_ declarations: [any ExperimentDeclaration]) {
        var seen: Set<ExperimentID> = []
        experiments = declarations.map(\.descriptor).filter { descriptor in
            let isNew = seen.insert(descriptor.id).inserted
            assert(isNew, "Experiment \(descriptor.id) is declared twice")
            return isNew
        }
    }

    public func descriptor(for id: ExperimentID) -> ExperimentDescriptor? {
        experiments.first { $0.id == id }
    }
}
