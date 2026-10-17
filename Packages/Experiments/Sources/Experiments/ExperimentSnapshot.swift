/// Every experiment's value at one moment, and the extension points they resolve to. A plain
/// value, so engines off the main actor resolve contracts from a snapshot the store hands them.
public struct ExperimentSnapshot: Sendable {
    public let catalog: ExperimentCatalog
    /// Only values the user changed from the default, each one the experiment accepts.
    public let overrides: [ExperimentID: StoredValue]

    public init(catalog: ExperimentCatalog, overrides: [ExperimentID: StoredValue]) {
        self.catalog = catalog
        self.overrides = overrides.filter { id, value in
            catalog.descriptor(for: id).map { $0.accepts(value) && $0.defaultValue != value } ?? false
        }
    }

    public func value(of gate: Gate) -> Bool {
        gate.value(from: overrides[gate.id])
    }

    public func value<Value>(of parameter: Parameter<Value>) -> Value {
        parameter.value(from: overrides[parameter.id])
    }

    public func isEnabled(_ variant: Variant) -> Bool {
        isEnabled(variant.id)
    }

    /// Whether a gate or variant is on; false for parameters and unknown ids.
    public func isEnabled(_ id: ExperimentID) -> Bool {
        value(for: id) == .bool(true)
    }

    /// The value in effect, saved or default; nil for an id the catalog doesn't declare.
    public func value(for id: ExperimentID) -> StoredValue? {
        overrides[id] ?? catalog.descriptor(for: id)?.defaultValue
    }

    /// The claims of every variant that's on.
    public var contributions: [Contribution] {
        catalog.experiments.flatMap { descriptor -> [Contribution] in
            guard case .variant(let claims) = descriptor.tier, isEnabled(descriptor.id) else { return [] }
            return claims.map { Contribution(source: .experiment(descriptor.id), claim: $0) }
        }
    }

    public var extensions: ExtensionResolver {
        ExtensionResolver(contributions: contributions)
    }

    public func implementation<Contract>(of point: ExtensionPoint<Contract>) -> Contract {
        extensions.implementation(of: point)
    }
}
