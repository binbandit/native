/// Why a copy has its outcome. A planned copy carries why it's due; every other copy carries
/// everything that stands in the way, not only the first.
public enum DataLifecycleReason: Hashable, Comparable, Sendable, CustomStringConvertible {
    // Why it's due.
    case requested
    case retentionExpired
    /// Removed before and listed again: a reindex or relisting brought it back.
    case tombstoned

    // Why it's kept.
    case notExpired
    case noRetentionPeriod
    /// The store's retention isn't set by policy.
    case noRetentionRule
    /// Another record that uses the copy isn't going.
    case sharedWithKeptRecord

    case legalHold(String)

    // What can't be established.
    case policyUnavailable
    case retentionPolicyUnusable
    case holdAuthorityUnavailable
    case holdAuthorityMalformed
    case timestampUnknown
    case timestampAfterPlanningTime
    case clockWentBack
    case integrationUnknown
    case copyNotInInventory
    case ownershipUnknown
    /// The owner says it belongs to someone other than the store's owner.
    case ownershipMismatch
    case locationUnknown
    /// Its path climbs out of its root.
    case locationOutsideRoot
    /// Its path is in an approved root, but not where the store keeps its copies.
    case locationOutsideStore
    case symbolicLink
    case linkStateUnknown

    // What's out of reach.
    case rootNotApproved
    case remoteOffline
    case availabilityUnknown

    // What Native can't or may not do.
    case externallyOwned
    case customerOwned
    case systemOwned
    /// Nothing of the user's to remove (runtime files, security state).
    case noUserData
    case adapterMissing(DataAdapterCapability)

    public var disposition: DataCopyOutcome.Disposition {
        switch self {
        case .requested, .retentionExpired, .tombstoned: .planned
        case .notExpired, .noRetentionPeriod, .noRetentionRule, .sharedWithKeptRecord: .kept
        case .legalHold: .held
        case .policyUnavailable, .retentionPolicyUnusable, .holdAuthorityUnavailable, .holdAuthorityMalformed,
            .timestampUnknown, .timestampAfterPlanningTime, .clockWentBack, .integrationUnknown, .copyNotInInventory,
            .ownershipUnknown, .ownershipMismatch, .locationUnknown, .locationOutsideRoot, .locationOutsideStore,
            .symbolicLink, .linkStateUnknown:
            .unknown
        case .rootNotApproved, .remoteOffline, .availabilityUnknown: .unreachable
        case .externallyOwned, .customerOwned, .systemOwned, .noUserData, .adapterMissing: .unsupported
        }
    }

    /// Kept for a reason that still lets the plan be complete: it simply isn't due.
    var isNotDue: Bool {
        self == .notExpired || self == .noRetentionPeriod || self == .noRetentionRule
    }

    public var description: String {
        switch self {
        case .requested: "requested"
        case .retentionExpired: "retention-expired"
        case .tombstoned: "tombstoned"
        case .notExpired: "not-expired"
        case .noRetentionPeriod: "no-retention-period"
        case .noRetentionRule: "no-retention-rule"
        case .sharedWithKeptRecord: "shared-with-kept-record"
        case .legalHold(let id): "legal-hold:\(id)"
        case .policyUnavailable: "policy-unavailable"
        case .retentionPolicyUnusable: "retention-policy-unusable"
        case .holdAuthorityUnavailable: "hold-authority-unavailable"
        case .holdAuthorityMalformed: "hold-authority-malformed"
        case .timestampUnknown: "timestamp-unknown"
        case .timestampAfterPlanningTime: "timestamp-after-planning-time"
        case .clockWentBack: "clock-went-back"
        case .integrationUnknown: "integration-unknown"
        case .copyNotInInventory: "copy-not-in-inventory"
        case .ownershipUnknown: "ownership-unknown"
        case .ownershipMismatch: "ownership-mismatch"
        case .locationUnknown: "location-unknown"
        case .locationOutsideRoot: "location-outside-root"
        case .locationOutsideStore: "location-outside-store"
        case .symbolicLink: "symbolic-link"
        case .linkStateUnknown: "link-state-unknown"
        case .rootNotApproved: "root-not-approved"
        case .remoteOffline: "remote-offline"
        case .availabilityUnknown: "availability-unknown"
        case .externallyOwned: "externally-owned"
        case .customerOwned: "customer-owned"
        case .systemOwned: "system-owned"
        case .noUserData: "no-user-data"
        case .adapterMissing(let capability): "adapter-missing:\(capability.rawValue)"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.description < rhs.description }
}
