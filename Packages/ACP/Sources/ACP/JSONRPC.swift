import Foundation

/// A JSON-RPC request id. Ours are always integers, but agents may use strings for theirs.
public enum RequestID: Hashable, Sendable, Codable {
    case int(Int)
    case string(String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let int): try container.encode(int)
        case .string(let string): try container.encode(string)
        }
    }
}

public struct RPCError: Error, Hashable, Sendable, Codable, LocalizedError {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public var errorDescription: String? { message }

    /// The agent's own account when it gives one: text `data` (or its `details`) under a generic
    /// `message`, the way codex-acp reports a configuration it can't load as "Internal error".
    public var detail: String {
        let text = (data?.stringValue ?? data?["details"]?.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return message }
        return text
    }

    static func methodNotFound(_ method: String) -> RPCError {
        RPCError(code: -32601, message: "Method not found: \(method)")
    }
}

/// A request the client sends to the agent, tied to the response type the agent returns for it.
public protocol ACPRequest: Encodable, Sendable {
    associatedtype Response: Decodable & Sendable
    static var method: String { get }
}

/// A one-way message the client sends to the agent.
public protocol ACPNotification: Encodable, Sendable {
    static var method: String { get }
}

/// For methods whose result carries nothing we use, such as `session/set_mode`.
public struct EmptyResponse: Decodable, Sendable {
    public init(from decoder: any Decoder) throws {}
}

// MARK: - Wire envelopes

struct OutgoingRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: RequestID
    let method: String
    let params: Params
}

struct OutgoingNotification<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: Params
}

struct OutgoingResult<Result: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: RequestID
    let result: Result
}

struct OutgoingError: Encodable {
    let jsonrpc = "2.0"
    let id: RequestID
    let error: RPCError
}

/// Just enough of an incoming message to route it; the payload is decoded again once its type is known.
struct IncomingEnvelope: Decodable {
    let id: RequestID?
    let method: String?
    let error: RPCError?
}

struct IncomingParams<Params: Decodable>: Decodable {
    let params: Params
}

struct IncomingResult<Result: Decodable>: Decodable {
    let result: Result
}
