import Foundation

/// A stable identifier for one kind of lifecycle subject, so a plan id can't be passed where an
/// operation id belongs.
public struct DataLifecycleID<Subject>: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String { value }
}

public typealias DataRequestID = DataLifecycleID<DataLifecycleRequest>
public typealias DataPlanID = DataLifecycleID<DataLifecyclePlan>
public typealias DataOperationID = DataLifecycleID<DataOperation>

/// A 64-bit FNV-1a digest of length-prefixed parts: the same parts give the same id on every
/// machine and launch, unlike `Hasher`. It identifies inputs; it isn't a security check.
enum StableDigest {
    static func of(_ parts: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for part in parts {
            for byte in "\(part.utf8.count):\(part);".utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x0000_0100_0000_01b3
            }
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// What a caller wants planned. The id is the caller's own and stays the same when a request is
/// planned again or resumed, so its operations keep their ids.
public struct DataLifecycleRequest: Equatable, Sendable {
    public enum Purpose: Equatable, Sendable {
        /// Remove what a retention period has expired.
        case retention
        /// Remove these records, and the records that belong to them, as someone asked.
        case erasure(Set<DataRecordKey>)
    }

    public let id: DataRequestID
    public let purpose: Purpose
    /// The stores it covers. Nil means its purpose's default: the stores a policy sets a period for
    /// (retention), or every store that can hold the user's data (erasure).
    public let stores: Set<DataStoreID>?

    /// Nil for an empty id, an erasure that names nothing, or an empty set of stores: a request
    /// that can't cover anything would plan as if there were nothing to do.
    public init?(id: String, purpose: Purpose, stores: Set<DataStoreID>? = nil) {
        if case .erasure(let keys) = purpose, keys.isEmpty || keys.contains(where: { $0.id.isEmpty }) { return nil }
        guard !id.isEmpty, stores?.isEmpty != true else { return nil }
        self.id = DataRequestID(id)
        self.purpose = purpose
        self.stores = stores
    }

}

/// The time a plan is made at, and how far the caller trusts it.
public struct DataPlanningClock: Equatable, Sendable {
    public var now: Date
    /// The latest time already trusted: the previous plan's time, or the newest time a store has
    /// recorded. A `now` before it means the clock went back, and nothing is due by age then.
    public var trustedFloor: Date?

    public init(now: Date, trustedFloor: Date? = nil) {
        self.now = now
        self.trustedFloor = trustedFloor
    }

    var hasGoneBack: Bool { trustedFloor.map { now < $0 } ?? false }
}
