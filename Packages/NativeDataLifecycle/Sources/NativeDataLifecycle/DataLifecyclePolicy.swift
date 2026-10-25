import NativePolicy

/// The part of a validated `NativePolicy` the planner uses: whether the policy can be trusted at all,
/// its revision, and each retention period it sets. A value the organization set badly is
/// `unusable`, never the stricter number the policy layer substitutes: for retention a smaller
/// number deletes more, so failing closed here means deleting nothing by it.
public struct DataLifecyclePolicy: Equatable, Sendable {
    public enum Retention: Equatable, Sendable {
        /// No period is set: nothing expires by policy.
        case unlimited
        case days(Int)
        /// The organization set a period Native can't use, so nothing is due by it.
        case unusable
    }

    /// False when the organization's configuration is unreadable or locked down, or the caller
    /// couldn't load a policy: nothing destructive is eligible then.
    public let isAvailable: Bool
    public let revision: PolicyRevision?
    private let retentions: [DataRetentionKey: Retention]

    public init(_ policy: NativePolicy) {
        var retentions: [DataRetentionKey: Retention] = [:]
        for key in DataRetentionKey.allCases {
            let days: Int? =
                switch key {
                case .searchRetentionDays: policy.searchRetentionDays
                }
            retentions[key] =
                if policy.keyStatus[key.policyKey]?.validity.isFailure == true {
                    .unusable
                } else if let days {
                    days > 0 ? .days(days) : .unusable
                } else {
                    .unlimited
                }
        }
        self.init(
            isAvailable: policy.deployment.lockdown == nil && policy.deployment.state != .unavailable,
            revision: policy.deployment.revision, retentions: retentions)
    }

    private init(isAvailable: Bool, revision: PolicyRevision?, retentions: [DataRetentionKey: Retention]) {
        self.isAvailable = isAvailable
        self.revision = revision
        self.retentions = retentions
    }

    /// For a caller that couldn't load a policy.
    public static let unavailable = DataLifecyclePolicy(isAvailable: false, revision: nil, retentions: [:])

    public func retention(_ key: DataRetentionKey) -> Retention {
        retentions[key] ?? .unusable
    }
}

extension DataRetentionKey {
    var policyKey: PolicyKey {
        switch self {
        case .searchRetentionDays: .searchRetentionDays
        }
    }
}
