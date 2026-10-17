import Foundation

/// An experiment's saved value, in one of the shapes a property list can hold.
public enum StoredValue: Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    public enum Kind: Hashable, Sendable {
        case bool, int, double, string
    }

    public var kind: Kind {
        switch self {
        case .bool: .bool
        case .int: .int
        case .double: .double
        case .string: .string
        }
    }

    /// The value as a property-list object, for `UserDefaults`.
    public var propertyList: Any {
        switch self {
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .string(let value): value
        }
    }

    /// Reads a property-list object as `kind`. Property lists store every number as `NSNumber`, so
    /// the expected kind, not the object, decides how a number is read.
    public init?(propertyList object: Any, as kind: Kind) {
        switch (kind, object) {
        case (.string, let string as String): self = .string(string)
        case (.bool, let number as NSNumber): self = .bool(number.boolValue)
        case (.int, let number as NSNumber): self = .int(number.intValue)
        case (.double, let number as NSNumber): self = .double(number.doubleValue)
        default: return nil
        }
    }
}
