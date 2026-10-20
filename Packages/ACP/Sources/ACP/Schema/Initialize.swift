import Foundation

public let protocolVersion = 1

public struct Implementation: Codable, Hashable, Sendable {
    public var name: String
    public var title: String?
    public var version: String?

    public init(name: String, title: String? = nil, version: String? = nil) {
        self.name = name
        self.title = title
        self.version = version
    }

    public var displayName: String { title ?? name }
}

public struct InitializeRequest: ACPRequest {
    public typealias Response = InitializeResponse
    public static let method = "initialize"

    public var protocolVersion: Int
    /// Native shows subagents as their own sessions; Cursor reads that from `_meta` and Claude from
    /// the top level. It answers form elicitations (Claude Code only offers its AskUserQuestion tool
    /// to clients that do). It implements no other optional client capabilities yet (fs, terminals,
    /// URL elicitation), so agents do that work themselves.
    public var clientCapabilities: [String: JSONValue] = [
        "subagents": .object([:]),
        "elicitation": .object(["form": .object([:])]),
        "_meta": .object(["subagents": .object([:])]),
    ]
    public var clientInfo: Implementation

    public init(protocolVersion: Int = ACP.protocolVersion, clientInfo: Implementation) {
        self.protocolVersion = protocolVersion
        self.clientInfo = clientInfo
    }
}

public struct InitializeResponse: Decodable, Sendable {
    public var protocolVersion: Int
    public var agentCapabilities: AgentCapabilities
    public var agentInfo: Implementation?
    public var authMethods: [AuthMethod]

    private enum CodingKeys: String, CodingKey {
        case protocolVersion, agentCapabilities, agentInfo, authMethods, _meta
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        agentCapabilities =
            try container.decodeIfPresent(AgentCapabilities.self, forKey: .agentCapabilities) ?? AgentCapabilities()
        agentInfo = try container.decodeIfPresent(Implementation.self, forKey: .agentInfo)
        authMethods = try container.decodeIfPresent([AuthMethod].self, forKey: .authMethods) ?? []
        // Steering is an extension, advertised beside the standard capabilities.
        let meta = try container.decodeIfPresent(JSONValue.self, forKey: ._meta)
        agentCapabilities.steering = meta?["steering"]?["supported"] == .bool(true)
    }
}

/// What an agent takes in a prompt besides text and `resource_link` blocks, which every agent
/// takes (`promptCapabilities`).
public struct PromptCapabilities: Decodable, Hashable, Sendable {
    public var image = false
    /// Whether `resource` blocks (a file's contents embedded in the prompt) are understood.
    public var embeddedContext = false

    public init(image: Bool = false, embeddedContext: Bool = false) {
        self.image = image
        self.embeddedContext = embeddedContext
    }

    private enum CodingKeys: String, CodingKey {
        case image, embeddedContext
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decodeIfPresent(Bool.self, forKey: .image) ?? false
        embeddedContext = try container.decodeIfPresent(Bool.self, forKey: .embeddedContext) ?? false
    }
}

public struct AgentCapabilities: Decodable, Hashable, Sendable {
    public var loadSession = false
    public var prompt = PromptCapabilities()
    /// Optional session methods, which ACP advertises by the presence of an (often empty) object.
    public var listSessions = false
    /// Whether `DeleteSessionRequest` removes sessions from the agent's own store.
    public var deleteSessions = false
    /// Whether `CloseSessionRequest` frees a session in the agent's process.
    public var closeSessions = false
    /// Whether `session/resume` reopens a session without replaying its history.
    public var resumeSessions = false
    /// Whether `SteerRequest` works (the `_session/steering` extension).
    public var steering = false
    /// Which remote MCP transports the agent can connect to; every agent supports stdio servers.
    public var mcpHTTP = false
    public var mcpSSE = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case loadSession, promptCapabilities, sessionCapabilities, mcpCapabilities
    }

    private struct MCPCapabilities: Decodable {
        var http: Bool?
        var sse: Bool?
    }

    private struct SessionCapabilities: Decodable {
        var list: JSONValue?
        var delete: JSONValue?
        var close: JSONValue?
        var resume: JSONValue?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loadSession = try container.decodeIfPresent(Bool.self, forKey: .loadSession) ?? false
        prompt =
            try container.decodeIfPresent(PromptCapabilities.self, forKey: .promptCapabilities) ?? PromptCapabilities()
        let session = try container.decodeIfPresent(SessionCapabilities.self, forKey: .sessionCapabilities)
        listSessions = session?.list.map { $0 != .null } ?? false
        deleteSessions = session?.delete.map { $0 != .null } ?? false
        closeSessions = session?.close.map { $0 != .null } ?? false
        resumeSessions = session?.resume.map { $0 != .null } ?? false
        let mcp = try container.decodeIfPresent(MCPCapabilities.self, forKey: .mcpCapabilities)
        mcpHTTP = mcp?.http ?? false
        mcpSSE = mcp?.sse ?? false
    }
}
