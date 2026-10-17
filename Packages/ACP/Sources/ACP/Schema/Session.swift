import Foundation

public struct SessionID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// An MCP server the client asks the agent to connect to for a session.
public enum MCPServer: Encodable, Hashable, Sendable {
    /// A local server the agent launches.
    case stdio(name: String, command: String, arguments: [String] = [], environment: [String: String] = [:])
    /// A remote server; agents advertise support with `mcpCapabilities.http`.
    case http(name: String, url: URL, headers: [String: String] = [:])

    private enum CodingKeys: String, CodingKey {
        case type, name, command, args, env, url, headers
    }

    /// ACP's `EnvVariable` and `HttpHeader` share this shape.
    private struct NameValue: Encodable {
        let name: String
        let value: String
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let pairs = { (dictionary: [String: String]) in dictionary.sorted { $0.key < $1.key }.map { NameValue(name: $0.key, value: $0.value) } }
        switch self {
        case .stdio(let name, let command, let arguments, let environment):
            try container.encode(name, forKey: .name)
            try container.encode(command, forKey: .command)
            try container.encode(arguments, forKey: .args)
            try container.encode(pairs(environment), forKey: .env)
        case .http(let name, let url, let headers):
            try container.encode("http", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(url.absoluteString, forKey: .url)
            try container.encode(pairs(headers), forKey: .headers)
        }
    }
}

// MARK: - Creating, loading and listing

public struct NewSessionRequest: ACPRequest {
    public typealias Response = NewSessionResponse
    public static let method = "session/new"

    public var cwd: String
    public var mcpServers: [MCPServer]

    public init(cwd: String, mcpServers: [MCPServer] = []) {
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

public struct NewSessionResponse: Decodable, Sendable {
    public var sessionId: SessionID
    public var configOptions: [ConfigOption]?
}

public struct LoadSessionRequest: ACPRequest {
    public typealias Response = LoadSessionResponse
    public static let method = "session/load"

    public var sessionId: SessionID
    public var cwd: String
    public var mcpServers: [MCPServer]

    public init(sessionId: SessionID, cwd: String, mcpServers: [MCPServer] = []) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

/// The agent replays the whole conversation as `session/update`s before answering this.
public struct LoadSessionResponse: Decodable, Sendable {
    public var configOptions: [ConfigOption]?
}

public struct ListSessionsRequest: ACPRequest {
    public typealias Response = ListSessionsResponse
    public static let method = "session/list"

    public var cwd: String?
    public var cursor: String?

    public init(cwd: String?, cursor: String? = nil) {
        self.cwd = cwd
        self.cursor = cursor
    }
}

public struct ListSessionsResponse: Decodable, Sendable {
    public var sessions: [SessionInfo]
    public var nextCursor: String?
}

public struct SessionInfo: Codable, Hashable, Sendable, Identifiable {
    public var sessionId: SessionID
    public var cwd: String
    public var title: String?
    /// ISO 8601, as the agent reports it.
    public var updatedAt: String?

    public init(sessionId: SessionID, cwd: String, title: String? = nil, updatedAt: Date? = nil) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt.map { $0.formatted(.iso8601) }
    }

    public var id: SessionID { sessionId }

    public var updatedDate: Date? {
        guard let updatedAt else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(updatedAt))
            ?? (try? Date.ISO8601FormatStyle().parse(updatedAt))
    }
}

// MARK: - Prompting

public struct PromptRequest: ACPRequest {
    public typealias Response = PromptResponse
    public static let method = "session/prompt"

    public var sessionId: SessionID
    public var prompt: [ContentBlock]

    public init(sessionId: SessionID, prompt: [ContentBlock]) {
        self.sessionId = sessionId
        self.prompt = prompt
    }
}

public struct PromptResponse: Decodable, Sendable {
    public var stopReason: StopReason
}

public enum StopReason: Hashable, Sendable, Decodable {
    case endTurn
    case maxTokens
    case maxTurnRequests
    case refusal
    case cancelled
    /// Only reported for subagents whose work failed.
    case error
    case other(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = switch raw {
        case "end_turn": .endTurn
        case "max_tokens": .maxTokens
        case "max_turn_requests": .maxTurnRequests
        case "refusal": .refusal
        case "cancelled": .cancelled
        case "error": .error
        default: .other(raw)
        }
    }
}

public struct CancelNotification: ACPNotification {
    public static let method = "session/cancel"

    public var sessionId: SessionID

    public init(sessionId: SessionID) {
        self.sessionId = sessionId
    }
}

// MARK: - Config options

public struct SetConfigOptionRequest: ACPRequest {
    public typealias Response = SetConfigOptionResponse
    public static let method = "session/set_config_option"

    public var sessionId: SessionID
    public var configId: String
    public var value: String

    public init(sessionId: SessionID, configId: String, value: String) {
        self.sessionId = sessionId
        self.configId = configId
        self.value = value
    }
}

public struct SetConfigOptionResponse: Decodable, Sendable {
    public var configOptions: [ConfigOption]
}

/// A session setting the agent exposes, such as its permission mode or model.
public struct ConfigOption: Decodable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    /// A hint such as `mode` or `model`; not an exhaustive set.
    public var category: String?
    public var kind: Kind

    public enum Kind: Hashable, Sendable {
        case select(currentValue: String, options: [SelectOption])
        /// Boolean options exist in ACP, but agents only send them to clients that opt in.
        case unsupported(type: String)
    }

    public struct SelectOption: Decodable, Hashable, Sendable, Identifiable {
        public var value: String
        public var name: String
        public var description: String?

        public var id: String { value }
    }

    private struct SelectGroup: Decodable {
        var options: [SelectOption]
    }

    /// Select options arrive either flat or grouped; Native shows them flat for now.
    private enum SelectEntry: Decodable {
        case option(SelectOption)
        case group(SelectGroup)

        init(from decoder: any Decoder) throws {
            self = if let group = try? SelectGroup(from: decoder) { .group(group) } else { .option(try SelectOption(from: decoder)) }
        }

        var options: [SelectOption] {
            switch self {
            case .option(let option): [option]
            case .group(let group): group.options
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, category, type, currentValue, options
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        let type = try container.decode(String.self, forKey: .type)
        if type == "select" {
            kind = .select(
                currentValue: try container.decode(String.self, forKey: .currentValue),
                options: try container.decode([SelectEntry].self, forKey: .options).flatMap(\.options)
            )
        } else {
            kind = .unsupported(type: type)
        }
    }
}

// MARK: - Steering

/// Adds a message to the turn that's running, so the agent can change course between tool calls
/// instead of after it finishes. An extension (`_session/steering`); agents advertise it with
/// `_meta.steering.supported` in their `initialize` result.
public struct SteerRequest: ACPRequest {
    public typealias Response = SteerResponse
    public static let method = "_session/steering"

    public var sessionId: SessionID
    public var prompt: [ContentBlock]
    /// Asks for `.promptRequired` instead of the agent starting a turn of its own when there's
    /// nothing left to steer, so the client keeps delivering prompts the usual way.
    private let _meta = Meta()

    public init(sessionId: SessionID, prompt: [ContentBlock]) {
        self.sessionId = sessionId
        self.prompt = prompt
    }

    private struct Meta: Encodable, Sendable {
        let steering = ["idleBehavior": "promptRequired"]
    }
}

public struct SteerResponse: Decodable, Sendable {
    public var outcome: Outcome

    public enum Outcome: Hashable, Sendable, Decodable {
        /// The message joined the running turn.
        case injected
        /// The turn had already ended and the message wasn't used; send it as a prompt.
        case promptRequired
        /// The turn had already ended and the agent started a new one itself (older agents).
        case startedNewTurn
        case other(String)

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = switch raw {
            case "injected": .injected
            case "promptRequired": .promptRequired
            case "startedNewTurn": .startedNewTurn
            default: .other(raw)
            }
        }
    }
}
