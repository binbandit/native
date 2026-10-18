import Foundation

// The runtime's line protocol (Runtime/ScriptRuntime/src/protocol.rs, docs/script-runtime.md).

/// The protocol version this package speaks.
let scriptProtocolVersion = 2

/// What the host sends the runtime.
enum ScriptInboundFrame: Encodable, Sendable {
    struct Binding: Encodable, Sendable {
        var path: [String]
        var toolName: String
    }

    case evaluate(code: String, bindings: [Binding], inputs: [String: String])
    case toolResult(id: UInt32, isError: Bool, content: ScriptJSON)

    private enum CodingKeys: String, CodingKey {
        case type, code, bindings, inputs, id, isError, content
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .evaluate(let code, let bindings, let inputs):
            try container.encode("evaluate", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(bindings, forKey: .bindings)
            try container.encode(inputs, forKey: .inputs)
        case .toolResult(let id, let isError, let content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(isError, forKey: .isError)
            try container.encode(content, forKey: .content)
        }
    }

    /// One line of the protocol, newline included.
    func line() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

/// What the runtime sends the host.
enum ScriptOutboundFrame: Decodable, Sendable, Equatable {
    case ready(protocolVersion: Int)
    case evaluationStarted
    /// A piece of one `text()` call; `end` marks its last piece.
    case text(String, end: Bool)
    case toolCall(id: UInt32, toolName: String, input: ScriptJSON, site: ScriptCallSite? = nil)
    case result
    case error(ScriptFailure)

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, text, end, id, toolName, input, error, line, column
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ready": self = .ready(protocolVersion: try container.decode(Int.self, forKey: .protocolVersion))
        case "evaluation_started": self = .evaluationStarted
        case "text":
            self = .text(
                try container.decode(String.self, forKey: .text), end: try container.decode(Bool.self, forKey: .end))
        case "tool_call":
            let line = try container.decodeIfPresent(Int.self, forKey: .line)
            self = .toolCall(
                id: try container.decode(UInt32.self, forKey: .id),
                toolName: try container.decode(String.self, forKey: .toolName),
                input: try container.decode(ScriptJSON.self, forKey: .input),
                site: line.map { ScriptCallSite(line: $0, column: try? container.decodeIfPresent(Int.self, forKey: .column)) })
        case "result": self = .result
        case "error": self = .error(try container.decode(ScriptFailure.self, forKey: .error))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown frame type \(type)")
        }
    }
}
