/// A JSON value kept as written, so a plugin's theme can be checked entry by entry instead of
/// failing the whole manifest when one is malformed.
public enum ThemeJSON: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ThemeJSON])
    case object([String: ThemeJSON])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ThemeJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: ThemeJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// An object's member, or nil for anything else.
    public subscript(key: String) -> ThemeJSON? {
        if case .object(let members) = self { members[key] } else { nil }
    }

    /// A string's value, or nil for anything else.
    public var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// An array's elements, or nil for anything else.
    public var array: [ThemeJSON]? {
        if case .array(let value) = self { value } else { nil }
    }
}
