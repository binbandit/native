/// An instruction to keep records, whatever retention or a deletion request says.
public struct LegalHold: Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        case everything
        case stores(Set<DataStoreID>)
        /// These records, and every record that belongs to one of them (a project's tasks).
        case records(Set<DataRecordKey>)
    }

    public let id: String
    public let scope: Scope

    public init(id: String, scope: Scope) {
        self.id = id
        self.scope = scope
    }

    /// Whether the hold keeps `record` in `store`, and with it any copy shared with the records in
    /// `sharedWith`: a copy several records use is kept when any of them is held.
    func keeps(_ record: DataRecord, in store: DataStoreID, sharedWith: Set<DataRecordKey> = []) -> Bool {
        switch scope {
        case .everything: true
        case .stores(let stores): stores.contains(store)
        case .records(let keys): !keys.isDisjoint(with: record.keys.union(sharedWith))
        }
    }

    var isWellFormed: Bool {
        guard !id.isEmpty else { return false }
        return switch scope {
        case .everything: true
        case .stores(let stores): !stores.isEmpty
        case .records(let keys): !keys.isEmpty && keys.allSatisfy { !$0.id.isEmpty }
        }
    }
}

/// What the caller learned from whoever decides holds. Native has no hold source of its own yet: the
/// caller reads one and reports it here, and "no holds" is something it has to confirm, never a
/// default. Anything but a confirmed, well-formed set keeps every destructive outcome from planning.
public struct LegalHoldAuthority: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        /// Read and well formed; `holds` is the complete set, possibly empty.
        case confirmed
        /// The source couldn't be read.
        case unavailable
        /// The source was read, but what it said can't be trusted (no revision, an empty or
        /// duplicated id, a hold that names nothing).
        case malformed
    }

    public let state: State
    /// Identifies the hold set the plan honored, for its record.
    public let revision: String?
    public let holds: [LegalHold]

    private init(state: State, revision: String?, holds: [LegalHold]) {
        self.state = state
        self.revision = revision
        self.holds = holds
    }

    /// Validates the set as a whole: one bad hold makes the whole authority malformed, since
    /// dropping it would silently release what it meant to keep.
    public static func confirmed(revision: String, holds: [LegalHold]) -> LegalHoldAuthority {
        let ids = holds.map(\.id)
        guard !revision.isEmpty, Set(ids).count == ids.count, holds.allSatisfy(\.isWellFormed) else {
            return LegalHoldAuthority(state: .malformed, revision: revision.isEmpty ? nil : revision, holds: [])
        }
        return LegalHoldAuthority(state: .confirmed, revision: revision, holds: holds)
    }

    public static let unavailable = LegalHoldAuthority(state: .unavailable, revision: nil, holds: [])

    /// The confirmed holds that keep this copy, by id.
    func holds(covering record: DataRecord, copy: DataRecordCopy, in store: DataStoreID) -> [String] {
        guard state == .confirmed else { return [] }
        return holds.filter { $0.keeps(record, in: store, sharedWith: copy.sharedWith) }.map(\.id).sorted()
    }

    /// Whether a confirmed hold keeps the record itself, whatever its copies.
    func isHolding(_ record: DataRecord, in store: DataStoreID) -> Bool {
        state == .confirmed && holds.contains { $0.keeps(record, in: store) }
    }
}
