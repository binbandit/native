import ACP
import Foundation
import NativeHostProtocol

// The ACP messages the host exchanges with agents, in the shapes it needs: it forwards most of what
// agents say verbatim, so payloads it doesn't interpret stay `JSONValue`.

struct RawSessionRequest: Decodable, Sendable {
    var sessionId: SessionID
}

struct RawPermissionRequest: Decodable, Sendable {
    struct ToolCall: Decodable, Sendable {
        var toolCallId: String
        var title: String?
    }

    var sessionId: SessionID
    var toolCall: ToolCall
}

struct RawNewSessionRequest: Encodable, Sendable {
    var cwd: String
    var mcpServers: [JSONValue]
    var _meta: JSONValue?
}

struct RawNewSessionResponse: Decodable, Sendable {
    var sessionId: SessionID
    var configOptions: JSONValue?
}

struct RawLoadSessionRequest: Encodable, Sendable {
    var sessionId: SessionID
    var cwd: String
    var mcpServers: [JSONValue]
    var _meta: JSONValue?
}

struct RawSessionIDRequest: Encodable, Sendable {
    var sessionId: SessionID
}

struct RawListSessionsRequest: Encodable, Sendable {
    var cwd: String?
    var cursor: String?
}

struct RawAuthenticateRequest: Encodable, Sendable {
    var methodId: String
}

struct RawConfigOptionsResponse: Decodable, Sendable {
    var configOptions: JSONValue?
}

struct RawSetConfigOptionRequest: Encodable, Sendable {
    var sessionId: SessionID
    var configId: String
    var value: String
}

struct RawPromptResponse: Decodable, Sendable {
    var stopReason: String
}

struct RawSteerResponse: Decodable, Sendable {
    var outcome: String
}

/// What the host tells agents about itself in `initialize`: what the app's own `InitializeRequest`
/// says. Subagents show as their own sessions (Cursor reads that from `_meta`, Claude from the top
/// level), and form elicitations are answered (Claude Code only offers AskUserQuestion to clients
/// that do). No other optional client capabilities yet (fs, terminals), so agents do that work.
struct HostInitializeRequest: Encodable, Sendable {
    var protocolVersion = ACP.protocolVersion
    var clientCapabilities: JSONValue = .object([
        "subagents": .object([:]), "elicitation": .object(["form": .object([:])]),
        "_meta": .object(["subagents": .object([:])]),
    ])
    var clientInfo: Implementation
}

extension SessionMirror {
    /// A `config_option_update`, for config options that came back in a response rather than an update.
    static func configOptionsUpdate(_ options: JSONValue) -> JSONValue {
        .object(["sessionUpdate": .string("config_option_update"), "configOptions": options])
    }
}
