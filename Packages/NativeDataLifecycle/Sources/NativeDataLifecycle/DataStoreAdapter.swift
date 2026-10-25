import NativePolicy

/// One planned removal, as an executor hands it to the store's adapter. It carries the plan's
/// policy and hold revisions: an adapter refuses an operation whose plan no longer matches them.
public struct DataOperation: Equatable, Sendable {
    public let id: DataOperationID
    public let plan: DataPlanID
    public let record: DataRecordKey
    public let store: DataStoreID
    public let copy: DataCopyKind
    public let location: DataRelativePath?
    public let capabilities: Set<DataAdapterCapability>
    public let policyRevision: PolicyRevision?
    public let holdRevision: String?
}

/// The future contract for one store's lifecycle. Nothing implements it yet: each store family gets
/// its adapter in its own change (docs/enterprise/data-lifecycle.md). An adapter:
/// - acts only on the operations a current plan gives it, and only on its own store;
/// - re-checks holds and the plan's revisions before each destructive step;
/// - is idempotent by operation id, so a crash resumes rather than repeats, and a copy already
///   gone verifies as removed;
/// - writes its tombstone in the same transaction as the delete when the store can be reimported;
/// - reports what remains outside its reach (backups, file system blocks) rather than claiming
///   an erasure the storage can't guarantee. Unlinking a file is not secure erasure on an SSD.
public protocol DataStoreAdapter: Sendable {
    var store: DataStoreID { get }
    var capabilities: Set<DataAdapterCapability> { get }

    func estimate(_ operations: [DataOperation]) async throws(DataAdapterFailure) -> DataEstimate
    /// Writes the copy's records under `destination`, inside a root the caller approved.
    func export(
        _ operation: DataOperation, to destination: DataRelativePath
    ) async throws(DataAdapterFailure)
        -> DataExportReceipt
    func delete(_ operation: DataOperation) async throws(DataAdapterFailure) -> DataDeletionReceipt
    func verify(_ operation: DataOperation) async throws(DataAdapterFailure) -> DataVerification
}

public struct DataEstimate: Equatable, Sendable {
    public let records: Int
    /// Nil when the store can't tell without reading content.
    public let bytes: Int64?

    public init(records: Int, bytes: Int64?) {
        self.records = records
        self.bytes = bytes
    }
}

public struct DataExportReceipt: Equatable, Sendable {
    public let operation: DataOperationID
    public let location: DataRelativePath
    public let bytes: Int64

    public init(operation: DataOperationID, location: DataRelativePath, bytes: Int64) {
        self.operation = operation
        self.location = location
        self.bytes = bytes
    }
}

public struct DataDeletionReceipt: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case removed
        /// Nothing was there: removed earlier, possibly by a run that crashed before reporting.
        case alreadyAbsent
    }

    public let operation: DataOperationID
    public let state: State
    public let tombstone: DataTombstone?
    public let remaining: [DataResidue]

    public init(operation: DataOperationID, state: State, tombstone: DataTombstone?, remaining: [DataResidue]) {
        self.operation = operation
        self.state = state
        self.tombstone = tombstone
        self.remaining = remaining
    }
}

public struct DataVerification: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case absent
        case present
        case unknown
    }

    public let operation: DataOperationID
    public let state: State
    public let remaining: [DataResidue]

    public init(operation: DataOperationID, state: State, remaining: [DataResidue]) {
        self.operation = operation
        self.state = state
        self.remaining = remaining
    }
}

/// Where a removed record can still be, past what its adapter controls.
public enum DataResidue: String, Equatable, Sendable {
    /// SQLite log frames, until a checkpoint truncates the log.
    case writeAheadLog
    /// Freed database pages, until a vacuum or secure delete overwrites them.
    case freePages
    /// Git objects, until `git gc` prunes them.
    case unreachableObjects
    /// File system blocks: unlinking frees them, and SSDs don't promise when they're erased.
    case storageBlocks
    /// Backups, snapshots and synced copies the customer keeps.
    case customerBackups
}

/// Why an adapter didn't carry an operation out. It names the problem, never the record's content.
public enum DataAdapterFailure: Error, Equatable, Sendable {
    /// A hold appeared after the plan was made.
    case held
    /// The policy or hold revision changed since the plan was made.
    case planStale
    case unreachable
    case unsupported(DataAdapterCapability)
    /// Interrupted partway; running the same operation again resumes it.
    case interrupted
    case failed(code: String)
}
