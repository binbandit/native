import Exec
import Foundation
import MCP

/// A change to an agent's own MCP configuration, made the agent's way: through its CLI, never by
/// editing its files. The exact command is shown before it runs, with secret values masked.
public struct AgentCLICommand: Hashable, Sendable, Identifiable {
    public enum Action: Hashable, Sendable {
        case add, remove, signIn
    }

    public var format: AgentConfigFormat
    public var action: Action
    public var serverName: String
    public var executable: String
    public var arguments: [String]
    /// Where it runs: a project's own scopes are the project's.
    public var directory: String?
    /// Values the arguments carry that mustn't be shown.
    var secrets: [String] = []

    public var id: String { ([executable] + arguments).joined(separator: " ") }

    /// The command line as the user reads it, secrets replaced with `•••`.
    public var displayText: String {
        let words = ([executable] + arguments).map { word in
            secrets.filter { !$0.isEmpty }.reduce(word) { $0.replacingOccurrences(of: $1, with: "•••") }
        }
        let line = ShellQuoting.commandLine(words)
        guard let directory else { return line }
        return "cd \(ShellQuoting.quote(directory)) && \(line)"
    }

    /// Sign-in opens a browser and waits for the user, so it gets minutes; the rest seconds.
    public func command(environment: [String: String]) -> Command {
        Command(executable, arguments, in: directory, environment: environment, timeout: action == .signIn ? .seconds(300) : .seconds(60))
    }
}

/// Why an agent's CLI can't make a change, and what the user can do instead.
public struct AgentCLIUnavailable: Error, Hashable, Sendable {
    public var message: String
}

public enum AgentCLI {
    public enum AddScope: Hashable, Sendable {
        case user
        /// Claude Code's private per-project scope.
        case local(URL)
        /// Checked into the project (`.mcp.json`).
        case project(URL)
    }

    /// Adds `server` to the agent's configuration.
    public static func add(_ server: MCPServerConfig, to format: AgentConfigFormat, scope: AddScope = .user) -> Result<AgentCLICommand, AgentCLIUnavailable> {
        switch format {
        case .claudeCode:
            // `add-json` takes the whole entry, so nothing depends on how flags and the name parse.
            let (scopeName, directory) = claudeScope(scope)
            let entry: JSON
            var secrets: [String] = []
            switch server.transport {
            case .stdio(let command, let arguments, let environment, _):
                entry = ["type": "stdio", "command": .string(command), "args": .array(arguments.map(JSON.string)), "env": .object(environment.mapValues(JSON.string))]
                secrets = Array(environment.values)
            case .http(let url, let headers), .sse(let url, let headers):
                entry = ["type": .string(server.transport.kind.rawValue), "url": .string(url.absoluteString), "headers": .object(headers.mapValues(JSON.string))]
                secrets = Array(headers.values)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let json = String(decoding: (try? encoder.encode(entry)) ?? Data(), as: UTF8.self)
            return .success(AgentCLICommand(
                format: format, action: .add, serverName: server.name, executable: "claude",
                arguments: ["mcp", "add-json", "--scope", scopeName, server.name, json], directory: directory, secrets: secrets
            ))
        case .codex:
            guard scope == .user else { return .failure(AgentCLIUnavailable(message: "Codex's CLI adds servers to your user config only.")) }
            switch server.transport {
            case .stdio(let command, let arguments, let environment, let directory):
                guard directory == nil else { return .failure(AgentCLIUnavailable(message: "Codex's CLI can't set a working directory; add it to ~/.codex/config.toml instead.")) }
                let variables = environment.keys.sorted().flatMap { ["--env", "\($0)=\(environment[$0] ?? "")"] }
                return .success(AgentCLICommand(
                    format: format, action: .add, serverName: server.name, executable: "codex",
                    arguments: ["mcp", "add", server.name] + variables + ["--", command] + arguments, secrets: Array(environment.values)
                ))
            case .http(let url, let headers):
                guard headers.isEmpty else { return .failure(AgentCLIUnavailable(message: "Codex's CLI can't set HTTP headers; add them to ~/.codex/config.toml as http_headers.")) }
                return .success(AgentCLICommand(format: format, action: .add, serverName: server.name, executable: "codex", arguments: ["mcp", "add", server.name, "--url", url.absoluteString]))
            case .sse:
                return .failure(AgentCLIUnavailable(message: "Codex doesn't connect to SSE servers."))
            }
        case .cursor:
            return .failure(AgentCLIUnavailable(message: "Cursor's CLI has no MCP commands; add it to ~/.cursor/mcp.json."))
        }
    }

    /// Removes an entry from the scope it's in.
    public static func remove(_ entry: ConfiguredServer) -> Result<AgentCLICommand, AgentCLIUnavailable> {
        switch (entry.format, entry.scope) {
        case (_, .plugin(let plugin)):
            return .failure(AgentCLIUnavailable(message: "It comes with the \(plugin) plugin; turn the plugin off in \(entry.format.displayName) to remove it."))
        case (_, .managed):
            return .failure(AgentCLIUnavailable(message: "Your administrator manages it."))
        case (.claudeCode, let scope):
            let (scopeName, directory): (String, String?) = switch scope {
            case .local(let project): ("local", ProjectPath.key(project))
            case .project(let project): ("project", ProjectPath.key(project))
            default: ("user", nil)
            }
            return .success(AgentCLICommand(format: .claudeCode, action: .remove, serverName: entry.name, executable: "claude", arguments: ["mcp", "remove", "--scope", scopeName, entry.name], directory: directory))
        case (.codex, .user):
            return .success(AgentCLICommand(format: .codex, action: .remove, serverName: entry.name, executable: "codex", arguments: ["mcp", "remove", entry.name]))
        case (.codex, _):
            return .failure(AgentCLIUnavailable(message: "Codex's CLI only changes your user config; edit the project's .codex/config.toml."))
        case (.cursor, _):
            return .failure(AgentCLIUnavailable(message: "Cursor's CLI has no MCP commands; edit \(entry.source.lastPathComponent)."))
        }
    }

    /// Runs the agent's own sign-in for a remote server: it opens the browser and keeps the token.
    public static func signIn(_ entry: ConfiguredServer) -> Result<AgentCLICommand, AgentCLIUnavailable> {
        guard entry.server.transport.kind != .stdio else { return .failure(AgentCLIUnavailable(message: "Local servers don't sign in.")) }
        switch entry.format {
        case .claudeCode:
            return .success(AgentCLICommand(format: .claudeCode, action: .signIn, serverName: entry.name, executable: "claude", arguments: ["mcp", "login", entry.name], directory: entry.scope.project.map(ProjectPath.key)))
        case .codex:
            return .success(AgentCLICommand(format: .codex, action: .signIn, serverName: entry.name, executable: "codex", arguments: ["mcp", "login", entry.name]))
        case .cursor:
            return .failure(AgentCLIUnavailable(message: "Sign in from Cursor's MCP settings."))
        }
    }

    private static func claudeScope(_ scope: AddScope) -> (String, String?) {
        switch scope {
        case .user: ("user", nil)
        case .local(let project): ("local", ProjectPath.key(project))
        case .project(let project): ("project", ProjectPath.key(project))
        }
    }
}
