/// What a store adapter can do. A plan names the ones each copy needs, so a store whose adapter
/// lacks one stays explicitly unsupported instead of half-done.
public enum DataAdapterCapability: String, CaseIterable, Codable, Comparable, Sendable {
    /// Count what an operation would touch, without touching it.
    case estimate
    case export
    case delete
    /// Remove what a delete leaves behind in the store itself: a SQLite checkpoint and vacuum, git
    /// pruning of objects nothing reaches.
    case compact
    /// Confirm afterwards that the copy is gone, reporting what remains outside the store.
    case verify
    /// Write a tombstone in the same step as the delete, so no import brings the record back.
    case tombstone

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}

extension DataCopyKind {
    /// What an adapter must be able to do before a plan can remove this kind of copy.
    func requiredCapabilities(tombstones: Bool) -> Set<DataAdapterCapability> {
        switch self {
        // Rows linger in the log and in free pages, and snapshots in unreachable objects, until the
        // store compacts.
        case .writeAheadLog, .sharedMemory, .gitObjects: [.compact, .verify]
        case .primary: tombstones ? [.delete, .verify, .tombstone] : [.delete, .verify]
        case .temporary, .trash, .reflog: [.delete, .verify]
        }
    }
}

/// Which capabilities each store's adapter has. Today no store has an adapter.
public struct DataAdapterSupport: Equatable, Sendable {
    private let capabilities: [DataStoreID: Set<DataAdapterCapability>]

    public init(_ capabilities: [DataStoreID: Set<DataAdapterCapability>] = [:]) {
        self.capabilities = capabilities
    }

    public init(adapters: [any DataStoreAdapter]) {
        var capabilities: [DataStoreID: Set<DataAdapterCapability>] = [:]
        for adapter in adapters {
            capabilities[adapter.store, default: []].formUnion(adapter.capabilities)
        }
        self.init(capabilities)
    }

    public static let none = DataAdapterSupport()

    public func capabilities(of store: DataStoreID) -> Set<DataAdapterCapability> {
        capabilities[store] ?? []
    }
}
