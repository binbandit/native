import ACP
import Foundation

// `JSONValue`'s `Decodable` conformance tries each type in turn and pays for a thrown error at every
// miss, about 28 µs for a one-line text chunk: on every streamed update a client decodes, that
// capped streaming through the host well below what agents send. These are the fast paths the host
// protocol uses instead (the host itself forwards updates without a `JSONValue`, see `AgentUpdate`).

extension JSONValue {
    /// Parses JSON text with `JSONSerialization` (about 4x faster than decoding a `JSONValue`).
    public init?(json data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        self.init(foundation: object)
    }

    private init(foundation object: Any) {
        switch object {
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            self = Self.isBoolean(number) ? .bool(number.boolValue) : .number(number.doubleValue)
        case let object as [String: Any]:
            self = .object(object.mapValues(JSONValue.init(foundation:)))
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(foundation:)))
        default:
            self = .null
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(Darwin)
        CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        String(cString: number.objCType) == "c"
        #endif
    }
}

/// Decodes a `JSONValue` trying the common cases first (strings, then objects), so most values
/// throw no error on the way: about 2.5x faster than `JSONValue`'s own conformance.
struct DecodedJSONValue: Decodable {
    let value: JSONValue

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            value = .null
        } else if let string = try? single.decode(String.self) {
            value = .string(string)
        } else if let object = try? decoder.container(keyedBy: Key.self) {
            var members: [String: JSONValue] = [:]
            for key in object.allKeys {
                members[key.stringValue] = try object.decode(DecodedJSONValue.self, forKey: key).value
            }
            value = .object(members)
        } else if var array = try? decoder.unkeyedContainer() {
            var elements: [JSONValue] = []
            while !array.isAtEnd {
                elements.append(try array.decode(DecodedJSONValue.self).value)
            }
            value = .array(elements)
        } else if let bool = try? single.decode(Bool.self) {
            value = .bool(bool)
        } else {
            value = .number(try single.decode(Double.self))
        }
    }
}

extension KeyedDecodingContainer {
    /// A `JSONValue`, the fast way (`DecodedJSONValue`).
    func decodeJSON(forKey key: Key) throws -> JSONValue {
        try decode(DecodedJSONValue.self, forKey: key).value
    }
}
