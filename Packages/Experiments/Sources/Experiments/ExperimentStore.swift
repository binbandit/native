import Observation

/// The user's experiment values: loaded from storage, changed in Labs, observed by whatever reads
/// them so a change applies live. Experiments that need a relaunch keep the value they had when
/// the app opened until it opens again.
@MainActor
@Observable
public final class ExperimentStore {
    /// The app's own experiments plus those of enabled plugins.
    public private(set) var catalog: ExperimentCatalog
    /// What the user chose, as Labs shows it.
    public private(set) var saved: ExperimentSnapshot

    /// Whether every experiment reads as its default, such as while an organization turns Labs
    /// off. The user's saved choices are kept, so they apply again once it's lifted.
    public var isFrozen = false

    @ObservationIgnored private let base: ExperimentCatalog
    @ObservationIgnored private let storage: any ExperimentStorage
    /// The saved values of experiments that need a relaunch, as they were when each first appeared
    /// (at launch, or when its plugin was turned on).
    @ObservationIgnored private var launchOverrides: [ExperimentID: StoredValue] = [:]
    @ObservationIgnored private var launched: Set<ExperimentID> = []

    public init(catalog: ExperimentCatalog, storage: any ExperimentStorage) {
        base = catalog
        self.catalog = catalog
        self.storage = storage
        saved = ExperimentSnapshot(catalog: catalog, overrides: [:])
        load()
    }

    /// Replaces the experiments plugins contribute, such as when one is turned on or off. Values
    /// stay in storage while a plugin is off or updated, so they come back with it.
    public func setContributedExperiments(_ descriptors: [ExperimentDescriptor]) {
        catalog = ExperimentCatalog(descriptors: base.experiments + descriptors)
        load()
    }

    private func load() {
        let loaded = catalog.experiments.reduce(into: [ExperimentID: StoredValue]()) { values, descriptor in
            values[descriptor.id] = storage.value(for: descriptor.id, as: descriptor.defaultValue.kind)
        }
        saved = ExperimentSnapshot(catalog: catalog, overrides: loaded)
        for descriptor in catalog.experiments where launched.insert(descriptor.id).inserted {
            if descriptor.requiresRelaunch {
                launchOverrides[descriptor.id] = saved.overrides[descriptor.id]
            }
        }
    }

    /// The values in effect now: the user's choices, except that experiments needing a relaunch
    /// still have their launch values, and nothing while frozen.
    public var current: ExperimentSnapshot {
        guard !isFrozen else { return ExperimentSnapshot(catalog: catalog, overrides: [:]) }
        let live = saved.overrides.filter { catalog.descriptor(for: $0.key)?.requiresRelaunch != true }
        return ExperimentSnapshot(catalog: catalog, overrides: live.merging(launchOverrides) { live, _ in live })
    }

    // MARK: Reading

    public func value(of gate: Gate) -> Bool {
        current.value(of: gate)
    }

    public func value<Value>(of parameter: Parameter<Value>) -> Value {
        current.value(of: parameter)
    }

    public func isEnabled(_ variant: Variant) -> Bool {
        current.isEnabled(variant)
    }

    public func implementation<Contract>(of point: ExtensionPoint<Contract>) -> Contract {
        current.implementation(of: point)
    }

    // MARK: Changing

    public func set(_ value: Bool, for gate: Gate) {
        setValue(.bool(value), for: gate.id)
    }

    public func set<Value>(_ value: Value, for parameter: Parameter<Value>) {
        setValue(value.stored, for: parameter.id)
    }

    public func setEnabled(_ isEnabled: Bool, for variant: Variant) {
        setValue(.bool(isEnabled), for: variant.id)
    }

    /// Saves a value for any experiment. Nil, the default, or a value the experiment doesn't
    /// accept forgets the saved one, so the experiment follows its default from then on.
    public func setValue(_ value: StoredValue?, for id: ExperimentID) {
        guard let descriptor = catalog.descriptor(for: id) else { return }
        let override = value.flatMap { descriptor.accepts($0) && $0 != descriptor.defaultValue ? $0 : nil }
        guard saved.overrides[id] != override else { return }
        storage.setValue(override, for: id)
        var overrides = saved.overrides
        overrides[id] = override
        saved = ExperimentSnapshot(catalog: catalog, overrides: overrides)
    }

    /// Replaces every saved value at once, such as to undo `resetAll()`.
    public func setOverrides(_ overrides: [ExperimentID: StoredValue]) {
        for descriptor in catalog.experiments {
            setValue(overrides[descriptor.id], for: descriptor.id)
        }
    }

    public func reset(_ id: ExperimentID) {
        setValue(nil, for: id)
    }

    public func resetAll() {
        setOverrides([:])
    }

    // MARK: State for Labs

    /// Experiments the user changed from their defaults, in catalog order.
    public var changed: [ExperimentID] {
        catalog.experiments.map(\.id).filter { saved.overrides[$0] != nil }
    }

    /// Whether the experiment's saved value differs from the one in effect until a relaunch.
    public func needsRelaunch(_ id: ExperimentID) -> Bool {
        catalog.descriptor(for: id)?.requiresRelaunch == true && saved.overrides[id] != launchOverrides[id]
    }

    /// Extension points the user's choices claim more than once.
    public var conflicts: [ExtensionConflict] {
        saved.extensions.conflicts
    }
}
