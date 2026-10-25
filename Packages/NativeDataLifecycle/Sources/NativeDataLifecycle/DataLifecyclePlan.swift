import Foundation
import NativePolicy

/// A dry run: what would happen to every copy in scope, and what the plan couldn't account for.
/// Making one changes nothing. It's `complete` only when every copy in scope is planned or not
/// due and every store in scope was listed, so partial coverage never reads as success.
public struct DataLifecyclePlan: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        /// Everything in scope is planned or not due, and every store was listed.
        case complete
        /// Some copies are planned; others are held, unsupported, unreachable or unknown, or a
        /// store wasn't listed.
        case partial
        /// Nothing can be planned, and something in scope is held or can't be accounted for.
        case blocked
        /// Every store was listed and nothing in scope is due.
        case nothingToDo
    }

    /// Changes whenever the inputs that decided the outcomes change (policy, holds, records), so an
    /// executor can tell a plan has gone stale. It doesn't depend on the time it was made.
    public let id: DataPlanID
    public let request: DataLifecycleRequest
    public let policyRevision: PolicyRevision?
    public let holdRevision: String?
    public let plannedAt: Date
    public let outcomes: [DataCopyOutcome]
    public let unaccounted: [DataUnaccountedStore]
    public let status: Status

    /// The planned outcomes, as operations an adapter takes.
    public var operations: [DataOperation] {
        outcomes.filter { $0.disposition == .planned }.map {
            DataOperation(
                id: $0.operation, plan: id, record: $0.record, store: $0.store, copy: $0.copy, location: $0.location,
                capabilities: $0.requiredCapabilities, policyRevision: policyRevision, holdRevision: holdRevision)
        }
    }

    /// The tombstones the planned removals leave once their adapters finish, so nothing imports the
    /// records again: one per record and store, from its first planned primary copy.
    public var tombstones: [DataTombstone] {
        var seen: Set<DataTombstone.Key> = []
        return outcomes.compactMap { outcome in
            guard outcome.disposition == .planned, outcome.requiredCapabilities.contains(.tombstone) else { return nil }
            let tombstone = DataTombstone(record: outcome.record, store: outcome.store, operation: outcome.operation)
            return seen.insert(tombstone.key).inserted ? tombstone : nil
        }
    }

    public func outcomes(for record: DataRecordKey) -> [DataCopyOutcome] {
        outcomes.filter { $0.record == record }
    }
}

/// What the plan says about one copy of one record.
public struct DataCopyOutcome: Equatable, Sendable {
    public enum Disposition: String, CaseIterable, Comparable, Sendable {
        /// An adapter would remove it.
        case planned
        /// Not due, or still needed by a record that stays.
        case kept
        /// No adapter can, or Native may not: it belongs to someone else.
        case unsupported
        /// Its root isn't approved, or its host is offline.
        case unreachable
        /// Something the plan relies on can't be established.
        case unknown
        /// A legal hold keeps it.
        case held

        /// Later cases win when a copy has several reasons.
        public static func < (lhs: Self, rhs: Self) -> Bool {
            allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
        }
    }

    /// Stable for this request, record, store, copy and location, so a resumed run can match the
    /// work it already finished.
    public let operation: DataOperationID
    public let record: DataRecordKey
    public let store: DataStoreID
    public let copy: DataCopyKind
    public let location: DataRelativePath?
    public let disposition: Disposition
    public let reasons: [DataLifecycleReason]
    /// What an adapter needs to carry it out, whether or not one exists.
    public let requiredCapabilities: Set<DataAdapterCapability>
}

/// A store in scope that the plan has no outcomes for, and why.
public struct DataUnaccountedStore: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// Native owns it, and its owner didn't list its records.
        case notListed
        /// Its owner tried and couldn't.
        case listingUnavailable
        /// The listing names a record twice or a record without copies, so it can't be trusted to
        /// be complete. The records it does list are still planned.
        case listingInconsistent
        /// Someone else owns it and nobody listed it for Native.
        case ownedOutsideNative
        /// Its integration isn't known yet.
        case integrationUnknown
        case notInInventory
    }

    public let store: DataStoreID
    public let reason: Reason
}
