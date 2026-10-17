import Foundation

/// What probing a server found: whether it connected, who it is and the tools it offers.
public struct MCPProbeReport: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case connected
        /// The server wants credentials the probe doesn't have, typically an OAuth sign-in.
        case needsAuth(MCPAuthChallenge)
        case failed(MCPProbeFailure)
    }

    public var status: Status
    public var server: MCPServerInfo?
    public var tools: [MCPToolInfo]
    /// The end of what a local server wrote to stderr: why it failed, usually.
    public var stderr: String
    public var startedAt: Date
    public var duration: Duration
    /// The transport that answered, which can differ from the configured one: a URL configured as
    /// Streamable HTTP may only speak SSE.
    public var transport: MCPTransport.Kind?
    /// UTF-8 size of the tool definitions (names, descriptions and input schemas) as the server
    /// sent them. Agents put these in the model's context, but how many tokens that makes depends
    /// on the agent: Claude Code counts rea's 1.9 MB as about 197k tokens, ten bytes a token, while
    /// a plain-prose definition is nearer four. Only the agent's own report gives the real figure.
    public var toolDefinitionBytes: Int

    public init(
        status: Status, server: MCPServerInfo? = nil, tools: [MCPToolInfo] = [], stderr: String = "",
        startedAt: Date, duration: Duration, transport: MCPTransport.Kind? = nil, toolDefinitionBytes: Int = 0
    ) {
        self.status = status
        self.server = server
        self.tools = tools
        self.stderr = stderr
        self.startedAt = startedAt
        self.duration = duration
        self.transport = transport
        self.toolDefinitionBytes = toolDefinitionBytes
    }

    public var isConnected: Bool {
        status == .connected
    }
}

public struct MCPServerInfo: Hashable, Sendable {
    public var name: String
    public var title: String?
    public var version: String?
    public var protocolVersion: String
    /// What the server tells the model about using it.
    public var instructions: String?

    public init(
        name: String, title: String? = nil, version: String? = nil, protocolVersion: String, instructions: String? = nil
    ) {
        self.name = name
        self.title = title
        self.version = version
        self.protocolVersion = protocolVersion
        self.instructions = instructions
    }
}

public struct MCPToolInfo: Hashable, Sendable, Identifiable {
    public var name: String
    public var title: String?
    public var description: String?
    /// The input schema's top-level properties, required ones first.
    public var parameters: [String]
    /// The server's `readOnlyHint` and `destructiveHint` annotations, when it gives them.
    public var isReadOnly: Bool?
    public var isDestructive: Bool?
    /// UTF-8 size of the tool's definition as sent: what it adds to an agent's context.
    public var definitionBytes: Int

    public init(
        name: String, title: String? = nil, description: String? = nil, parameters: [String] = [],
        isReadOnly: Bool? = nil, isDestructive: Bool? = nil, definitionBytes: Int = 0
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.parameters = parameters
        self.isReadOnly = isReadOnly
        self.isDestructive = isDestructive
        self.definitionBytes = definitionBytes
    }

    public var id: String { name }
}

/// Why a server wouldn't connect, in words for the user, at the step it stopped.
public struct MCPProbeFailure: Hashable, Sendable {
    public enum Stage: String, Hashable, Sendable {
        case launch, connect, initialize, listTools
    }

    public var stage: Stage
    public var message: String
    /// A local server's exit status, when it exited.
    public var exitStatus: Int32?

    public init(stage: Stage, message: String, exitStatus: Int32? = nil) {
        self.stage = stage
        self.message = message
        self.exitStatus = exitStatus
    }
}

/// A remote server turning the probe away for want of credentials.
public struct MCPAuthChallenge: Hashable, Sendable {
    public var statusCode: Int
    /// Where the server describes its authorization (RFC 9728), from `WWW-Authenticate`.
    public var resourceMetadata: URL?
    /// Whether the configuration sent credentials of its own (an `Authorization` header), which the
    /// server then rejected.
    public var sentCredentials: Bool

    public init(statusCode: Int, resourceMetadata: URL? = nil, sentCredentials: Bool) {
        self.statusCode = statusCode
        self.resourceMetadata = resourceMetadata
        self.sentCredentials = sentCredentials
    }

    /// Reads `resource_metadata="…"` from a `WWW-Authenticate` header.
    static func resourceMetadata(in header: String?) -> URL? {
        guard let header, let range = header.range(of: "resource_metadata=") else { return nil }
        var value = header[range.upperBound...]
        if value.hasPrefix("\"") {
            value = value.dropFirst().prefix { $0 != "\"" }
        } else {
            value = value.prefix { $0 != "," && $0 != " " }
        }
        return URL(string: String(value))
    }
}
