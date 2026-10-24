import Foundation

/// An agent CLI whose own MCP configuration Native can read. The raw values match
/// `AgentManifest.mcpConfig`.
public enum AgentConfigFormat: String, Hashable, Sendable, Codable, CaseIterable {
    case claudeCode = "claude-code"
    case codex
    case cursor

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    /// The CLI that manages the configuration, when it has MCP commands (Cursor's doesn't).
    public var cli: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .cursor: nil
        }
    }
}

/// An MCP server an agent loads from its own configuration.
public struct ConfiguredServer: Hashable, Sendable, Identifiable {
    /// Where the agent's configuration puts the server, which decides the projects it loads in.
    public enum Scope: Hashable, Sendable {
        /// Every project (`~/.claude.json`, `~/.codex/config.toml`, `~/.cursor/mcp.json`).
        case user
        /// One project, kept private to the user (Claude Code's "local" scope in `~/.claude.json`).
        case local(URL)
        /// One project, checked into it (`.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`).
        case project(URL)
        /// Contributed by one of the agent's own plugins.
        case plugin(String)
        /// Set by an administrator; it replaces everything else.
        case managed

        public var project: URL? {
            switch self {
            case .local(let url), .project(let url): url
            case .user, .plugin, .managed: nil
            }
        }

        public var displayName: String {
            switch self {
            case .user: "User"
            case .local: "Local"
            case .project: "Project"
            case .plugin(let name): "Plugin \(name)"
            case .managed: "Managed"
            }
        }
    }

    public enum Status: Hashable, Sendable {
        case enabled
        /// Turned off in the agent's configuration.
        case disabled
        /// Turned off for the project the entry was evaluated in.
        case disabledInProject
        /// A project server the agent asks the user to approve before loading.
        case awaitingApproval

        public var isLoaded: Bool { self == .enabled }
    }

    public var server: MCPServerConfig
    public var format: AgentConfigFormat
    public var scope: Scope
    /// The file the entry comes from.
    public var source: URL
    public var status: Status
    /// How the agent fills in values when it launches the server.
    public var resolution: ValueResolution
    /// Facts worth showing beside it, such as "Bearer token from $LINEAR_TOKEN".
    public var notes: [String]
    /// Read from the agent's shared credential owner, so it applies to every task using this entry.
    public var authentication: MCPAuthenticationStatus = .unknown

    public init(
        server: MCPServerConfig, format: AgentConfigFormat, scope: Scope, source: URL,
        status: Status = .enabled, resolution: ValueResolution = .none, notes: [String] = []
    ) {
        self.server = server
        self.format = format
        self.scope = scope
        self.source = source
        self.status = status
        self.resolution = resolution
        self.notes = notes
    }

    public var name: String { server.name }

    public var id: String {
        "\(format.rawValue)|\(scope)|\(server.name)"
    }

    /// The configuration as the agent would launch it in `project`, with variables filled in from
    /// `environment` (the user's login-shell environment).
    public func resolved(environment: [String: String], project: URL?) -> MCPServerConfig {
        resolution.resolve(server, environment: environment, project: project)
    }
}

/// How an agent expands values in a server's configuration before launching it.
public enum ValueResolution: Hashable, Sendable {
    case none
    /// Claude Code: `${VAR}` and `${VAR:-default}` in the command, arguments, environment, URL and
    /// headers.
    case claudeCode
    /// Cursor: `${env:VAR}`, `${userHome}`, `${workspaceFolder}` and `${workspaceFolderBasename}`.
    case cursor
    /// Codex: variables passed through by name, and headers or a bearer token read from variables.
    case codex(passThrough: [String], bearerTokenVariable: String?, headerVariables: [String: String])

    func resolve(_ server: MCPServerConfig, environment: [String: String], project: URL?) -> MCPServerConfig {
        var server = server
        switch self {
        case .none:
            break
        case .claudeCode, .cursor:
            let expand = { (text: String) in
                Interpolation.expand(text, style: self, environment: environment, project: project)
            }
            server.transport = server.transport.mapValues(expand)
        case .codex(let passThrough, let bearer, let headerVariables):
            switch server.transport {
            case .stdio(let command, let arguments, var variables, let directory):
                for name in passThrough where variables[name] == nil {
                    variables[name] = environment[name]
                }
                server.transport = .stdio(
                    command: command, arguments: arguments, environment: variables, workingDirectory: directory)
            case .http(let url, var headers), .sse(let url, var headers):
                for (header, variable) in headerVariables {
                    if let value = environment[variable] { headers[header] = value }
                }
                if let bearer, let token = environment[bearer] {
                    headers["Authorization"] = "Bearer \(token)"
                }
                server.transport =
                    server.transport.kind == .sse ? .sse(url: url, headers: headers) : .http(url: url, headers: headers)
            }
        }
        return server
    }
}

extension MCPTransport {
    /// Applies `transform` to every string a user writes in the configuration.
    func mapValues(_ transform: (String) -> String) -> MCPTransport {
        switch self {
        case .stdio(let command, let arguments, let environment, let directory):
            .stdio(
                command: transform(command), arguments: arguments.map(transform),
                environment: environment.mapValues(transform), workingDirectory: directory.map(transform))
        case .http(let url, let headers):
            .http(url: Self.map(url, transform), headers: headers.mapValues(transform))
        case .sse(let url, let headers):
            .sse(url: Self.map(url, transform), headers: headers.mapValues(transform))
        }
    }

    /// `URL` percent-encodes the braces of `${VAR}`, so they're put back before expanding.
    private static func map(_ url: URL, _ transform: (String) -> String) -> URL {
        let raw = url.absoluteString.replacingOccurrences(of: "%7B", with: "{").replacingOccurrences(
            of: "%7D", with: "}")
        return URL(string: transform(raw)) ?? url
    }
}
