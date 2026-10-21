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

/// A prompt's answer, for telling whether a model took part: ACP's `usage` is null for a command
/// the agent handled itself.
struct RawPromptUsageResponse: Decodable, Sendable {
    var stopReason: String
    var usage: JSONValue?
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

extension HostInitializeRequest {
    /// For an agent started to sign in with a `link` method: URL elicitations too, which agents
    /// offer device codes to. Only then, since agents also send sessions' URL elicitations (an MCP
    /// server's sign-in page) once they're advertised, and sessions don't show those yet.
    init(clientInfo: Implementation, advertisesLinks: Bool) {
        self.init(clientInfo: clientInfo)
        if advertisesLinks {
            clientCapabilities = clientCapabilities.merging(.object(["elicitation": .object(["url": .object([:])])]))
        }
    }
}

extension SessionMirror {
    /// A `config_option_update`, for config options that came back in a response rather than an update.
    static func configOptionsUpdate(_ options: JSONValue) -> JSONValue {
        .object(["sessionUpdate": .string("config_option_update"), "configOptions": options])
    }
}
