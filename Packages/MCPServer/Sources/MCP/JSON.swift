import Foundation

/// A JSON value: JSON-RPC messages, tool arguments, schemas and structured results.
public enum JSON: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public subscript(key: String) -> JSON? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    public var objectValue: [String: JSON]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    /// Converts any `Encodable` value, such as a tool's structured result.
    public init(encoding value: some Encodable) throws {
        self = try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(value))
    }

    /// Decodes this value as `type`, such as a tool's arguments.
    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        // A JSON value always encodes.
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }
}

extension JSON: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before Double: JSONDecoder won't read `true` as a number, but other decoders might.
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSON].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        // Whole numbers go out without a fraction, so integer request ids echo back unchanged.
        case .number(let number) where number.rounded() == number && abs(number) < 1e15:
            try container.encode(Int64(number))
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}

// Literals make schemas and results readable where they're written.
extension JSON: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
