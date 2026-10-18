import Foundation

/// Where policy values come from: the organization's managed values, and the user's own preferences
/// under the same keys.
public protocol PolicySource: Sendable {
    /// The organization's value for `key`, or nil when it doesn't manage it.
    func managedValue(forKey key: String) -> Any?
    /// The user's own value for `key`, or nil.
    func userValue(forKey key: String) -> Any?
    /// Every key the organization sets, when the source can list them; used to report unknown keys.
    var managedKeys: [String]? { get }
}

/// macOS: a configuration profile's settings appear as forced values in the app's defaults.
public struct UserDefaultsPolicySource: PolicySource, @unchecked Sendable {
    // UserDefaults is thread-safe; it just isn't annotated Sendable on every SDK.
    private let defaults: UserDefaults
    private let simulatedManagedKeys: Set<String>

    /// `simulatedManagedKeys` treats those keys as forced. A profile can't be installed on a
    /// development Mac without enrolling it, so debug builds use this to try policies out.
    public init(defaults: UserDefaults = .standard, simulatedManagedKeys: Set<String> = []) {
        self.defaults = defaults
        self.simulatedManagedKeys = simulatedManagedKeys
    }

    public func managedValue(forKey key: String) -> Any? {
        guard defaults.objectIsForced(forKey: key) || simulatedManagedKeys.contains(key) else { return nil }
        return defaults.object(forKey: key)
    }

    public func userValue(forKey key: String) -> Any? {
        guard !defaults.objectIsForced(forKey: key), !simulatedManagedKeys.contains(key) else { return nil }
        return defaults.object(forKey: key)
    }

    public var managedKeys: [String]? {
        guard !simulatedManagedKeys.isEmpty else { return nil }
        return Array(simulatedManagedKeys)
    }
}

/// iPadOS: managed apps receive their settings as one dictionary in the managed app configuration.
public struct ManagedAppConfigurationPolicySource: PolicySource, @unchecked Sendable {
    /// The key MDM servers deliver managed app configuration under.
    public static let configurationKey = "com.apple.configuration.managed"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var configuration: [String: Any] {
        defaults.dictionary(forKey: Self.configurationKey) ?? [:]
    }

    public func managedValue(forKey key: String) -> Any? {
        configuration[key]
    }

    public func userValue(forKey key: String) -> Any? {
        configuration[key] == nil ? defaults.object(forKey: key) : nil
    }

    public var managedKeys: [String]? {
        Array(configuration.keys)
    }
}

/// Values held in memory, for tests and previews.
public struct StaticPolicySource: PolicySource, @unchecked Sendable {
    // Property-list values only, which are immutable once stored here.
    private let managed: [String: Any]
    private let user: [String: Any]

    public init(managed: [String: Any] = [:], user: [String: Any] = [:]) {
        self.managed = managed
        self.user = user
    }

    public func managedValue(forKey key: String) -> Any? { managed[key] }
    public func userValue(forKey key: String) -> Any? { user[key] }
    public var managedKeys: [String]? { Array(managed.keys) }
}
