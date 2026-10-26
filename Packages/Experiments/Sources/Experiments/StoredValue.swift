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
    /// the expected kind, not the object, decides how a number is read. Launch arguments
    /// (`-experiment.<id> YES`) arrive as strings, so a switch also reads the words
    /// `UserDefaults.bool(forKey:)` accepts; anything else is unset, never on.
    public init?(propertyList object: Any, as kind: Kind) {
        switch (kind, object) {
        case (.string, let string as String): self = .string(string)
        case (.bool, let number as NSNumber): self = .bool(number.boolValue)
        case (.bool, let text as String):
            switch text.lowercased() {
            case "yes", "true", "1": self = .bool(true)
            case "no", "false", "0": self = .bool(false)
            default: return nil
            }
        case (.int, let number as NSNumber): self = .int(number.intValue)
        case (.double, let number as NSNumber): self = .double(number.doubleValue)
        default: return nil
        }
    }
}

extension StoredValue: Codable {
    /// A JSON scalar: `true`, `3`, `1.5` or `"roomy"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

extension StoredValue {
    /// The value as text, for an environment variable or an argument.
    public var text: String {
        switch self {
        case .bool(let value): String(value)
        case .int(let value): String(value)
        case .double(let value): value.formatted(.number.grouping(.never))
        case .string(let value): value
        }
    }
}
