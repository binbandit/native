import Foundation

/// A GraphQL request body for `gh api graphql --input -`, which takes variables of any type (gh's
/// `-f`/`-F` flags can't pass arrays or objects, and would put user text on the command line).
struct GraphQLRequest: Encodable, Sendable {
    /// A JSON value for a variable.
    enum Value: Encodable, Sendable, Hashable, ExpressibleByStringLiteral,
        ExpressibleByIntegerLiteral,
        ExpressibleByBooleanLiteral
    {
        case string(String)
        case int(Int)
        case bool(Bool)
        case null
        case array([Value])
        case object([String: Value])

        init(stringLiteral value: String) { self = .string(value) }
        init(integerLiteral value: Int) { self = .int(value) }
        init(booleanLiteral value: Bool) { self = .bool(value) }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .null: try container.encodeNil()
            case .array(let values): try container.encode(values)
            case .object(let values): try container.encode(values)
            }
        }
    }

    var query: String
    var variables: [String: Value]

    var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Strings, numbers and nested values of them always encode.
        return (try? encoder.encode(self)) ?? Data()
    }
}
