import Foundation

/// Where an `ExperimentStore` keeps the values the user changed.
public protocol ExperimentStorage: Sendable {
    /// The saved value, read as `kind`; nil when there's none or it isn't a `kind`.
    func value(for id: ExperimentID, as kind: StoredValue.Kind) -> StoredValue?
    /// Saves `value`, or forgets the saved one when it's nil.
    func setValue(_ value: StoredValue?, for id: ExperimentID)
}

/// Keeps each value under `experiment.<id>` in user defaults, so one can be set by hand:
/// `defaults write <bundle id> experiment.bubbles -bool YES`.
// UserDefaults is documented as thread-safe but isn't marked Sendable.
public struct UserDefaultsExperimentStorage: ExperimentStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func value(for id: ExperimentID, as kind: StoredValue.Kind) -> StoredValue? {
        defaults.object(forKey: Self.key(for: id)).flatMap { StoredValue(propertyList: $0, as: kind) }
    }

    public func setValue(_ value: StoredValue?, for id: ExperimentID) {
        if let value {
            defaults.set(value.propertyList, forKey: Self.key(for: id))
        } else {
            defaults.removeObject(forKey: Self.key(for: id))
        }
    }

    public static func key(for id: ExperimentID) -> String {
        "experiment.\(id.rawValue)"
    }
}
