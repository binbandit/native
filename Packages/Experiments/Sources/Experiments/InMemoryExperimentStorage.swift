import Synchronization

/// Keeps values in memory only, for previews and tests.
public final class InMemoryExperimentStorage: ExperimentStorage {
    private let values: Mutex<[ExperimentID: StoredValue]>

    public init(_ values: [ExperimentID: StoredValue] = [:]) {
        self.values = Mutex(values)
    }

    public func value(for id: ExperimentID, as kind: StoredValue.Kind) -> StoredValue? {
        values.withLock { $0[id] }.flatMap { $0.kind == kind ? $0 : nil }
    }

    public func setValue(_ value: StoredValue?, for id: ExperimentID) {
        values.withLock { $0[id] = value }
    }
}
