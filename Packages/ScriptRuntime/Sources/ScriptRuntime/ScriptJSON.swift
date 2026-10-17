import Foundation

/// A JSON value: what tools take and return, and what scripts see. Other JSON types (the MCP
/// package's `JSON`, ACP's `JSONValue`) convert through `init(encoding:)` and `decode(_:)`.
public enum ScriptJSON: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ScriptJSON])
    case object([String: ScriptJSON])

    public subscript(key: String) -> ScriptJSON? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    /// Converts any `Encodable` value, such as another JSON type or a structured result.
    public init(encoding value: some Encodable) throws {
        self = try JSONDecoder().decode(ScriptJSON.self, from: JSONEncoder().encode(value))
    }

    /// Decodes this value as `type`, such as a tool's typed arguments.
    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }

    /// Compact JSON text.
    public var jsonText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        // A JSON value always encodes.
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }
}

extension ScriptJSON: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before Double: some decoders read `true` as a number.
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([ScriptJSON].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: ScriptJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        // Whole numbers go out without a fraction, so ids and counts read as integers in scripts.
        case .number(let number) where number.rounded() == number && abs(number) < 1e15:
            try container.encode(Int64(number))
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}

extension ScriptJSON: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: ScriptJSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, ScriptJSON)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
