import ACP
import Foundation
import NativeAutomation

/// Extends Native. Native's own agents and features are plugins too, so every extension point is
/// exercised by built-in code before anything else depends on it.
///
/// A plugin is either code compiled into Native, or a `plugin.json` manifest in
/// `~/.native/plugins/<id>/` that contributes data (agents, MCP servers) without code.
protocol NativePlugin: Sendable {
    /// Who the plugin is and the data it contributes.
    var manifest: PluginManifest { get }
    /// Names sessions after what they're about.
    var titler: (any SessionTitler)? { get }
    /// MCP servers to hand the agent for a session, in addition to the manifest's static ones.
    /// Lets a plugin give agents tools scoped to the session that uses them.
    func mcpServers(for session: SessionContext) -> [MCPServer]
    /// Session lifecycle hooks, delivered to every enabled plugin in order.
    func handle(_ event: SessionEvent) async
    /// Whether the plugin runs before the user has chosen. Native starts minimal (see
    /// `docs/decisions.md`), so built-ins that add to what a new user sees start off; a manifest the
    /// user installed is on.
    var isEnabledByDefault: Bool { get }
}

extension NativePlugin {
    var isEnabledByDefault: Bool { true }
    var titler: (any SessionTitler)? { nil }
    func mcpServers(for session: SessionContext) -> [MCPServer] { [] }
    func handle(_ event: SessionEvent) async {}
}

// MARK: - Manifest

/// The `plugin.json` format, and the data half of every plugin.
struct PluginManifest: Codable, Hashable, Sendable, Identifiable {
    /// Unique across plugins; also the folder name for manifest plugins.
    var id: String
    var name: String
    var version: String?
    var description: String?
    var agents: [AgentManifest] = []
    var mcpServers: [MCPServerManifest] = []
    /// Multi-agent workflows the plugin offers (`WorkflowDefinition`'s JSON). A broken one is listed
    /// with its problems rather than failing the plugin.
    var workflows: [WorkflowDefinition] = []

    init(
        id: String, name: String, version: String? = nil, description: String? = nil, agents: [AgentManifest] = [],
        mcpServers: [MCPServerManifest] = [], workflows: [WorkflowDefinition] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.agents = agents
        self.mcpServers = mcpServers
        self.workflows = workflows
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        agents = try container.decodeIfPresent([AgentManifest].self, forKey: .agents) ?? []
        mcpServers = try container.decodeIfPresent([MCPServerManifest].self, forKey: .mcpServers) ?? []
        workflows = try container.decodeIfPresent([WorkflowDefinition].self, forKey: .workflows) ?? []
    }
}

/// An agent that speaks ACP over stdio.
struct AgentManifest: Codable, Hashable, Sendable {
    /// Stable across launches: sessions and their titles are remembered by it.
    var id: String
    var name: String
    /// An SF Symbol shown where there's only room for an icon.
    var symbol: String?
    /// Looked up on the user's login-shell PATH.
    var command: String
    var args: [String] = []
    var env: [String: String] = [:]
    /// Variables to set to the absolute path of a command on the user's PATH, such as
    /// `{"CLAUDE_CODE_EXECUTABLE": "claude"}`, so an adapter runs the user's own CLI.
    var resolveExecutables: [String: String] = [:]
    /// Where the agent keeps its own MCP configuration ("claude-code", "codex" or "cursor"), so the
    /// MCP feature can show and import the servers it already loads. Nil when unknown.
    var mcpConfig: String?
    /// Where the agent's icon comes from. Nil, or nothing found, draws a monogram of its name.
    var icon: AgentIconSource?
    /// Commands besides `command` that must be on the user's PATH for the agent to count as
    /// installed, such as the CLI an adapter drives (`claude` for an `npx` adapter).
    var requires: [String] = []
    /// How to install the agent and sign in, for the Add Agent list and the not-installed state.
    var setup: AgentSetupGuide?

    init(
        id: String, name: String, symbol: String? = nil, command: String, args: [String] = [],
        env: [String: String] = [:], resolveExecutables: [String: String] = [:], mcpConfig: String? = nil,
        icon: AgentIconSource? = nil, requires: [String] = [], setup: AgentSetupGuide? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.command = command
        self.args = args
        self.env = env
        self.resolveExecutables = resolveExecutables
        self.mcpConfig = mcpConfig
        self.icon = icon
        self.requires = requires
        self.setup = setup
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        resolveExecutables = try container.decodeIfPresent([String: String].self, forKey: .resolveExecutables) ?? [:]
        mcpConfig = try container.decodeIfPresent(String.self, forKey: .mcpConfig)
        icon = try container.decodeIfPresent(AgentIconSource.self, forKey: .icon)
        requires = try container.decodeIfPresent([String].self, forKey: .requires) ?? []
        setup = try container.decodeIfPresent(AgentSetupGuide.self, forKey: .setup)
    }
}

/// Where an agent's icon comes from, tried in this order. Native never ships other products'
/// artwork: it uses the copy already on the user's machine, or fetches the registry's at runtime.
struct AgentIconSource: Codable, Hashable, Sendable {
    /// An image file: an SVG, drawn in the text color like a glyph, or a bitmap. Relative paths
    /// are inside the plugin's folder. In `plugin.json`, `"icon": "icon.svg"` is short for this.
    var path: String?
    /// Apps whose icon stands for the agent, by bundle identifier; the first one installed wins.
    var apps: [String] = []
    /// The agent's id in the ACP registry, whose monochrome icon is fetched and cached.
    var registry: String?

    init(path: String? = nil, apps: [String] = [], registry: String? = nil) {
        self.path = path
        self.apps = apps
        self.registry = registry
    }

    init(from decoder: any Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) {
            self.init(path: path)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        apps = try container.decodeIfPresent([String].self, forKey: .apps) ?? []
        registry = try container.decodeIfPresent(String.self, forKey: .registry)
    }
}

/// How a user gets an agent going. Native shows these and never runs them.
struct AgentSetupGuide: Codable, Hashable, Sendable {
    /// A command to paste in a terminal that installs the agent without replacing anything else.
    var install: String?
    /// The agent's own install and sign-in docs.
    var docs: URL?
    /// A terminal command that signs in, for agents whose sign-in can't happen over ACP.
    var signIn: String?
}

/// An MCP server every agent session should get: `command` for a local (stdio) server, or `url`
/// for a remote (HTTP) one.
struct MCPServerManifest: Codable, Hashable, Sendable {
    var name: String
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var url: URL?
    var headers: [String: String]?

    var server: MCPServer? {
        switch (command, url) {
        case (let command?, nil): .stdio(name: name, command: command, arguments: args ?? [], environment: env ?? [:])
        case (nil, let url?): .http(name: name, url: url, headers: headers ?? [:])
        default: nil
        }
    }
}

// MARK: - Agents at runtime

/// An agent contributed by an enabled plugin.
struct AgentDefinition: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable, Codable, CustomStringConvertible {
        let rawValue: String
        var description: String { rawValue }
    }

    let id: ID
    let pluginID: String
    let manifest: AgentManifest

    init(_ manifest: AgentManifest, pluginID: String) {
        self.id = ID(rawValue: manifest.id)
        self.pluginID = pluginID
        self.manifest = manifest
    }

    var displayName: String { manifest.name }
    var symbolName: String { manifest.symbol ?? "sparkle" }

    func command(environment: [String: String]) -> AgentCommand {
        var environment = environment.merging(manifest.env) { $1 }
        for (variable, executable) in manifest.resolveExecutables {
            if let path = Self.executable(named: executable, in: environment) {
                environment[variable] = path
            }
        }
        return AgentCommand(
            executable: manifest.command,
            arguments: manifest.args,
            environment: environment,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private static func executable(named name: String, in environment: [String: String]) -> String? {
        environment["PATH", default: ""].split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: name).path(percentEncoded: false) }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Sessions as plugins see them

/// A session, described for plugins.
struct SessionContext: Hashable, Sendable {
    /// Native's own identity for the session, assigned before the agent creates it. Plugins key
    /// per-session resources (like an MCP server URL) by it, since those are handed over in
    /// `session/new` before the agent's id exists.
    var clientID: UUID
    var agent: AgentDefinition.ID
    var agentName: String
    /// The agent's id for the session; nil while `session/new` is in flight.
    var sessionID: SessionID?
    var cwd: URL
    var title: String?
    /// Set when the session is a subagent of another session.
    var parentID: SessionID?
}

enum SessionEvent: Sendable {
    case sessionStarted(SessionContext)
    case promptSent(SessionContext, text: String)
    case turnEnded(SessionContext, StopReason)
    /// A turn that failed with an error instead of ending with a stop reason. `items` are what the
    /// turn added after the user's prompt, so a plugin can tell whether the agent got anywhere.
    case turnFailed(SessionContext, prompt: String, error: any Error, items: [TranscriptItem])
    case permissionRequested(SessionContext, toolCall: String)
    /// A live context and cost report (not one replayed by `session/load`). Claude Code's
    /// rate-limit status rides on it as `usage.rateLimit`.
    case usageUpdated(SessionContext, Usage)
}

// MARK: - Titles

/// Writes a short title for a session from what the user asked for.
protocol SessionTitler: Sendable {
    /// Returns nil when it can't produce a title right now (for example, no model is available).
    func title(for request: TitleRequest) async throws -> String?
}

struct TitleRequest: Hashable, Sendable {
    var projectName: String
    /// The user's first prompt in the session.
    var prompt: String
}
