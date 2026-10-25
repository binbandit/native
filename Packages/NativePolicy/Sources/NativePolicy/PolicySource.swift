import Foundation

/// The organization's value for one key, as its source delivered it.
public enum ManagedEntry {
    /// The organization doesn't set the key.
    case absent
    case value(Any)
    /// The organization sets the key, but its value can't be trusted: another domain shadows it,
    /// or the container it arrived in is malformed. Native denies rather than guessing.
    case unreadable
}

/// Whether a source could read the organization's configuration as a whole.
public enum ManagedSourceStatus: String, Equatable, Sendable {
    /// Read normally; each key is then absent, a value or unreadable on its own.
    case available
    /// Delivered, but not in a shape Native can read (a managed app configuration that isn't a
    /// dictionary). Every managed key is unreadable.
    case malformed
    /// The source can't be read at all on this platform or right now.
    case unavailable
}

/// Where policy values come from: the organization's managed values, and the user's own preferences
/// under the same keys.
public protocol PolicySource: Sendable {
    /// The organization's value for `key`, telling a key it doesn't set from one it set badly.
    func managedEntry(forKey key: String) -> ManagedEntry
    /// The user's own value for `key`, or nil.
    func userValue(forKey key: String) -> Any?
    /// Every key the organization sets, when the source can list them; used to report unknown keys.
    var managedKeys: [String]? { get }
    var managedStatus: ManagedSourceStatus { get }
    /// Remembers restricted deployment across restarts (`PolicyEnrollmentStore`); nil forgets it.
    var enrollment: (any PolicyEnrollmentStore)? { get }
}

extension PolicySource {
    public var managedStatus: ManagedSourceStatus { .available }
    public var enrollment: (any PolicyEnrollmentStore)? { nil }

    /// The organization's value, or nil when it doesn't set one or it can't be read.
    public func managedValue(forKey key: String) -> Any? {
        if case .value(let value) = managedEntry(forKey: key) { value } else { nil }
    }
}

/// macOS: a configuration profile's settings appear as forced values in the app's defaults.
public struct UserDefaultsPolicySource: PolicySource, @unchecked Sendable {
    // UserDefaults is thread-safe; it just isn't annotated Sendable on every SDK.
    private let defaults: UserDefaults
    private let simulatedManagedKeys: Set<String>
    private let isForced: @Sendable (String) -> Bool
    private let launchArguments: @Sendable () -> [String: Any]
    public let enrollment: (any PolicyEnrollmentStore)?

    /// `simulatedManagedKeys` treats those keys as forced. A profile can't be installed on a
    /// development Mac without enrolling it, so debug builds use this to try policies out.
    public init(
        defaults: UserDefaults = .standard, simulatedManagedKeys: Set<String> = [],
        enrollment: (any PolicyEnrollmentStore)? = nil
    ) {
        nonisolated(unsafe) let forcedDefaults = defaults
        self.init(
            defaults: defaults, simulatedManagedKeys: simulatedManagedKeys, enrollment: enrollment,
            isForced: { forcedDefaults.objectIsForced(forKey: $0) },
            launchArguments: { UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain) })
    }

    /// Tests stand in for configuration profiles and launch arguments, which they can't install.
    init(
        defaults: UserDefaults, simulatedManagedKeys: Set<String>, enrollment: (any PolicyEnrollmentStore)?,
        isForced: @escaping @Sendable (String) -> Bool, launchArguments: @escaping @Sendable () -> [String: Any]
    ) {
        self.defaults = defaults
        self.simulatedManagedKeys = simulatedManagedKeys
        self.enrollment = enrollment
        self.isForced = isForced
        self.launchArguments = launchArguments
    }

    public func managedEntry(forKey key: String) -> ManagedEntry {
        let simulated = simulatedManagedKeys.contains(key)
        guard simulated || isForced(key) else { return .absent }
        // A launch argument sits in front of most domains, so a forced key it also names can't be
        // told apart from the user's argument. Simulated keys are set that way on purpose.
        guard simulated || launchArguments()[key] == nil, let value = defaults.object(forKey: key) else {
            return .unreadable
        }
        return .value(value)
    }

    public func userValue(forKey key: String) -> Any? {
        guard !isForced(key), !simulatedManagedKeys.contains(key) else { return nil }
        return defaults.object(forKey: key)
    }

    /// Forced values sit in the defaults search list, so the merged representation lists every key a
    /// profile sets, including misspelled ones that no known key would ever read.
    public var managedKeys: [String]? {
        let forced = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(PolicyKey.prefix) && isForced($0)
        }
        return Array(simulatedManagedKeys.union(forced))
    }
}

/// iPadOS: managed apps receive their settings as one dictionary in the managed app configuration.
public struct ManagedAppConfigurationPolicySource: PolicySource, @unchecked Sendable {
    /// The key MDM servers deliver managed app configuration under.
    public static let configurationKey = "com.apple.configuration.managed"

    private let defaults: UserDefaults
    public let enrollment: (any PolicyEnrollmentStore)?

    public init(defaults: UserDefaults = .standard, enrollment: (any PolicyEnrollmentStore)? = nil) {
        self.defaults = defaults
        self.enrollment = enrollment
    }

    private var delivered: Any? {
        defaults.object(forKey: Self.configurationKey)
    }

    public var managedStatus: ManagedSourceStatus {
        delivered == nil || delivered is [String: Any] ? .available : .malformed
    }

    public func managedEntry(forKey key: String) -> ManagedEntry {
        guard let delivered else { return .absent }
        guard let configuration = delivered as? [String: Any] else { return .unreadable }
        return configuration[key].map(ManagedEntry.value) ?? .absent
    }

    public func userValue(forKey key: String) -> Any? {
        // A malformed configuration may have meant to manage any key, so the user's value can't stand.
        guard case .absent = managedEntry(forKey: key) else { return nil }
        return defaults.object(forKey: key)
    }

    public var managedKeys: [String]? {
        guard let delivered else { return [] }
        return (delivered as? [String: Any]).map { Array($0.keys) }
    }
}

/// Values held in memory, for tests and previews.
public struct StaticPolicySource: PolicySource, @unchecked Sendable {
    // Property-list values only, which are immutable once stored here.
    private let managed: [String: Any]
    private let user: [String: Any]
    public let managedStatus: ManagedSourceStatus
    public let enrollment: (any PolicyEnrollmentStore)?

    public init(
        managed: [String: Any] = [:], user: [String: Any] = [:], status: ManagedSourceStatus = .available,
        enrollment: (any PolicyEnrollmentStore)? = nil
    ) {
        self.managed = managed
        self.user = user
        self.managedStatus = status
        self.enrollment = enrollment
    }

    public func managedEntry(forKey key: String) -> ManagedEntry {
        guard managedStatus == .available else { return managed[key] == nil ? .absent : .unreadable }
        return managed[key].map(ManagedEntry.value) ?? .absent
    }

    public func userValue(forKey key: String) -> Any? { user[key] }
    public var managedKeys: [String]? { Array(managed.keys) }
}
