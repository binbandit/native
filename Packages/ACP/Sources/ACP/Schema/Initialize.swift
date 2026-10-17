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

public struct AuthMethod: Decodable, Hashable, Sendable {
    /// A sign-in that only works in a terminal, so `authenticate` can't do it: the client runs a
    /// command in a terminal for the user instead.
    public enum Terminal: Hashable, Sendable {
        /// ACP's `"type": "terminal"`: run the agent's own command with these arguments.
        case agent(arguments: [String])
        /// Zed's `_meta["terminal-auth"]`: run this command.
        case command(String, arguments: [String])
    }

    public var id: String
    public var name: String
    public var description: String?
    /// Set when the method only works in a terminal.
    public var terminal: Terminal?

    public init(id: String, name: String, description: String? = nil, terminal: Terminal? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.terminal = terminal
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, type, args, _meta
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        let terminalAuth = try container.decodeIfPresent(JSONValue.self, forKey: ._meta)?["terminal-auth"]
        if let command = terminalAuth?["command"]?.stringValue {
            terminal = .command(command, arguments: Self.strings(terminalAuth?["args"]))
        } else if try container.decodeIfPresent(String.self, forKey: .type) == "terminal" {
            terminal = .agent(arguments: try container.decodeIfPresent([String].self, forKey: .args) ?? [])
        }
    }

    private static func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let values) = value else { return [] }
        return values.compactMap(\.stringValue)
    }
}

public struct AgentCapabilities: Decodable, Hashable, Sendable {
    public var loadSession = false
    public var image = false
    /// Optional session methods, which ACP advertises by the presence of an (often empty) object.
    public var listSessions = false
    /// Whether `DeleteSessionRequest` removes sessions from the agent's own store.
    public var deleteSessions = false
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

    private struct PromptCapabilities: Decodable {
        var image: Bool?
    }

    private struct SessionCapabilities: Decodable {
        var list: JSONValue?
        var delete: JSONValue?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loadSession = try container.decodeIfPresent(Bool.self, forKey: .loadSession) ?? false
        image = try container.decodeIfPresent(PromptCapabilities.self, forKey: .promptCapabilities)?.image ?? false
        let session = try container.decodeIfPresent(SessionCapabilities.self, forKey: .sessionCapabilities)
        listSessions = session?.list.map { $0 != .null } ?? false
        deleteSessions = session?.delete.map { $0 != .null } ?? false
        let mcp = try container.decodeIfPresent(MCPCapabilities.self, forKey: .mcpCapabilities)
        mcpHTTP = mcp?.http ?? false
        mcpSSE = mcp?.sse ?? false
    }
}
