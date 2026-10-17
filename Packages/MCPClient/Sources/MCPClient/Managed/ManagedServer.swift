import Foundation

/// An MCP server Native hands to agents itself: configured once, given to every agent (or the
/// ones chosen) in every project (or the ones chosen). Environment and header values are secrets
/// kept apart, in a `SecretStore`; only their names are stored with the server.
public struct ManagedServer: Identifiable, Hashable, Sendable, Codable {
    public enum Transport: Hashable, Sendable, Codable {
        case stdio(command: String, arguments: [String], environmentNames: [String], workingDirectory: String?)
        case http(url: URL, headerNames: [String])

        public var kind: MCPTransport.Kind {
            switch self {
            case .stdio: .stdio
            case .http: .http
            }
        }

        public var secretNames: [String] {
            switch self {
            case .stdio(_, _, let names, _), .http(_, let names): names
            }
        }

        public var endpoint: MCPEndpointIdentity {
            config(name: "", secrets: ManagedServerSecrets()).endpoint
        }

        /// The command line or URL, without any secrets.
        public var summary: String {
            config(name: "", secrets: ManagedServerSecrets()).transport.summary
        }

        func config(name: String, secrets: ManagedServerSecrets) -> MCPServerConfig {
            switch self {
            case .stdio(let command, let arguments, let names, let directory):
                MCPServerConfig(name: name, transport: .stdio(command: command, arguments: arguments, environment: secrets.environment.filter { names.contains($0.key) }, workingDirectory: directory))
            case .http(let url, let names):
                MCPServerConfig(name: name, transport: .http(url: url, headers: secrets.headers.filter { names.contains($0.key) }))
            }
        }
    }

    /// Everything, or a chosen few.
    public enum Selection: Hashable, Sendable, Codable {
        case all
        case only([String])

        public func includes(_ value: String) -> Bool {
            switch self {
            case .all: true
            case .only(let values): values.contains(value)
            }
        }
    }

    public var id: UUID
    /// What agents call it; tools appear to the model as `mcp__<name>__<tool>`.
    public var name: String
    public var transport: Transport
    public var isEnabled: Bool
    /// Agent ids (`AgentDefinition.ID`).
    public var agents: Selection
    /// Project paths (`ProjectPath.key`); a session in a folder inside one counts as in it.
    public var projects: Selection
    /// Projects it's turned off in, such as after failing there ("Disable for this project").
    public var excludedProjects: [String]
    /// Where it was imported from, such as "Claude Code · ~/.claude.json".
    public var origin: String?

    public init(
        id: UUID = UUID(), name: String, transport: Transport, isEnabled: Bool = true,
        agents: Selection = .all, projects: Selection = .all, excludedProjects: [String] = [], origin: String? = nil
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.isEnabled = isEnabled
        self.agents = agents
        self.projects = projects
        self.excludedProjects = excludedProjects
        self.origin = origin
    }

    /// The server as an agent gets it, secrets filled in.
    public func config(with secrets: ManagedServerSecrets) -> MCPServerConfig {
        transport.config(name: name, secrets: secrets)
    }

    /// Whether a session working in `directory` is in one of the chosen projects.
    public func includes(directory: URL?) -> Bool {
        let path = directory.map(ProjectPath.key)
        let contains = { (paths: [String]) in path.map { path in paths.contains { path == $0 || path.hasPrefix($0 == "/" ? $0 : $0 + "/") } } ?? false }
        if contains(excludedProjects) { return false }
        guard case .only(let paths) = projects else { return true }
        return contains(paths)
    }

    /// Names agents accept: letters, digits, `-` and `_`. Claude Code joins the name into tool
    /// names, so anything else would break them.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }
}

/// A managed server's secret values, by variable or header name.
public struct ManagedServerSecrets: Hashable, Sendable, Codable {
    public var environment: [String: String]
    public var headers: [String: String]

    public init(environment: [String: String] = [:], headers: [String: String] = [:]) {
        self.environment = environment
        self.headers = headers
    }

    public var isEmpty: Bool {
        environment.isEmpty && headers.isEmpty
    }
}

extension ManagedServer {
    /// A managed copy of an agent's server, so every agent gets it. Values move to `secrets`.
    /// Nil for SSE servers, which agents can't be handed over ACP.
    public static func importing(_ entry: ConfiguredServer, resolvedWith environment: [String: String] = [:], projects: Selection = .all) -> (ManagedServer, ManagedServerSecrets)? {
        // Variables the agent fills in at launch (Codex's pass-through names, bearer tokens) are
        // resolved now, so the copy works for agents that don't know the convention.
        let config = entry.resolution.isLiteral ? entry.server : entry.resolved(environment: environment, project: entry.scope.project)
        let transport: Transport
        let secrets: ManagedServerSecrets
        switch config.transport {
        case .stdio(let command, let arguments, let variables, let directory):
            transport = .stdio(command: command, arguments: arguments, environmentNames: variables.keys.sorted(), workingDirectory: directory)
            secrets = ManagedServerSecrets(environment: variables)
        case .http(let url, let headers):
            transport = .http(url: url, headerNames: headers.keys.sorted())
            secrets = ManagedServerSecrets(headers: headers)
        case .sse:
            return nil
        }
        let name = entry.name.hasPrefix("plugin:") ? String(entry.name.split(separator: ":").last ?? Substring(entry.name)) : entry.name
        let server = ManagedServer(name: name, transport: transport, projects: projects, origin: "\(entry.format.displayName) · \(entry.scope.displayName)")
        return (server, secrets)
    }
}

extension ValueResolution {
    /// Configurations that use none of the agent's variables can be copied exactly.
    var isLiteral: Bool {
        switch self {
        case .none: true
        case .claudeCode, .cursor: false
        case .codex(let passThrough, let bearer, let headers): passThrough.isEmpty && bearer == nil && headers.isEmpty
        }
    }
}
