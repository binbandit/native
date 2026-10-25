/// Says a record was removed from a store and must not come back: a reindex or a relisting that
/// finds it again in a source (an agent's history) skips it. It carries ids only, no content.
public struct DataTombstone: Hashable, Codable, Sendable {
    public let record: DataRecordKey
    public let store: DataStoreID
    /// The operation that removed it.
    public let operation: DataOperationID

    public init(record: DataRecordKey, store: DataStoreID, operation: DataOperationID) {
        self.record = record
        self.store = store
        self.operation = operation
    }
}

/// The tombstones a caller has kept. A record a store lists again despite its tombstone is planned
/// for removal again, whatever its age.
public struct DataTombstoneLedger: Equatable, Sendable {
    private let byRecord: [DataTombstone.Key: DataTombstone]

    public init(_ tombstones: [DataTombstone] = []) {
        var byRecord: [DataTombstone.Key: DataTombstone] = [:]
        for tombstone in tombstones where byRecord[tombstone.key] == nil {
            byRecord[tombstone.key] = tombstone
        }
        self.byRecord = byRecord
    }

    public func tombstone(for record: DataRecordKey, in store: DataStoreID) -> DataTombstone? {
        byRecord[DataTombstone.Key(record: record, store: store)]
    }

    /// Whether an import may add the record to the store.
    public func permitsImport(of record: DataRecordKey, into store: DataStoreID) -> Bool {
        tombstone(for: record, in: store) == nil
    }

    public func adding(_ tombstones: [DataTombstone]) -> DataTombstoneLedger {
        DataTombstoneLedger(Array(byRecord.values) + tombstones)
    }
}

extension DataTombstone {
    struct Key: Hashable {
        let record: DataRecordKey
        let store: DataStoreID
    }

    var key: Key { Key(record: record, store: store) }
}
