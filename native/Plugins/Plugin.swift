import ACP
import AIInstructions
import AppAppearance
import CodeThemes
import Experiments
import Foundation
import NativeAutomation
import NativeHostProtocol
import NativePolicy
import Search
import TaskDefaults

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
    /// Finishes what agents' launches depend on, such as reading the configuration a launch policy
    /// comes from. Agents wait for every enabled plugin's before they launch.
    func prepareForLaunch() async
    /// Whether the plugin runs before the user has chosen. Native starts minimal (see
    /// `docs/decisions.md`), so built-ins that add to what a new user sees start off; a manifest the
    /// user installed is on.
    var isEnabledByDefault: Bool { get }
    /// Built-in features own their policy gate; the registry enforces it before loading contributions.
    func isAllowed(by policy: NativePolicy) -> Bool
    /// What the plugin does that policy decides on as a whole. Restricted mode admits it only when
    /// every one is permitted, and keeps a plugin that hasn't declared (nil) off, built in or not.
    /// Ordinary mode doesn't consult it.
    var capabilities: Set<PolicyCapability>? { get }
    /// What the plugin wants left out of a session (MCP servers, skills), as intent. Every enabled
    /// plugin's policy is merged, and the session's agent applies what it can.
    func sessionPolicy(for session: SessionContext) -> SessionPolicy
    /// What it wants left out of every session of `agent`, for agents that apply policy at launch.
    func launchPolicy(for agent: AgentDefinition.ID) -> SessionPolicy
    /// For a plugin that provides agents: how they apply a policy in their own terms. Nil means
    /// they can't, and the UI says so.
    var policyTranslator: (any SessionPolicyTranslator)? { get }
    /// Experiments the plugin offers in Settings ▸ Labs (docs/plugins.md, Experiments): gates and
    /// parameters its code reads, and variants claiming extension points. Ids start with the
    /// plugin's id (`acme.fast-mode`). They're gone while the plugin is off.
    var experiments: [any ExperimentDeclaration] { get }
    /// For a plugin that provides agents: a reader for `agent`'s own record of its past sessions, so
    /// search covers sessions Native never loaded (docs/search.md). Nil means they're indexed as
    /// Native loads them.
    func historyReader(for agent: AgentDefinition.ID) -> (any SessionHistoryReader)?
    /// Tools for the task screen (docs/session-tools.md, "Adding a tool"), listed in the well and
    /// on Settings ▸ Task Tools after Native's own, with the same on and off switch and an
    /// assignable key. Ids start with the plugin's id (`acme.board`), and a tool lives beside the
    /// conversation or over it; others are left out. They're gone while the plugin is off.
    var sessionTools: [SessionToolContribution] { get }
}

extension NativePlugin {
    var isEnabledByDefault: Bool { true }
    func isAllowed(by policy: NativePolicy) -> Bool { true }
    var capabilities: Set<PolicyCapability>? { nil }
    var titler: (any SessionTitler)? { nil }
    func mcpServers(for session: SessionContext) -> [MCPServer] { [] }
    func handle(_ event: SessionEvent) async {}
    func prepareForLaunch() async {}
    func sessionPolicy(for session: SessionContext) -> SessionPolicy { .none }
    func launchPolicy(for agent: AgentDefinition.ID) -> SessionPolicy { .none }
    var policyTranslator: (any SessionPolicyTranslator)? { nil }
    var experiments: [any ExperimentDeclaration] { [] }
    func historyReader(for agent: AgentDefinition.ID) -> (any SessionHistoryReader)? { nil }
    var sessionTools: [SessionToolContribution] { [] }
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
    /// Code themes and accent palettes (`docs/plugins.md`, Themes). Data only, checked one by one
    /// when used, so a broken theme is reported rather than failing the plugin.
    var themes = ThemeContributions()
    /// App icon families (a plain theme, or a celebration's artwork), validated one by one with their
    /// images inside the plugin's folder (`AppearanceCatalog`).
    var iconSets = IconSetContributions()
    /// Celebrations with their calendars, offered in Settings ▸ Celebrations, each off until chosen.
    /// A malformed one is listed with its problem rather than failing the plugin.
    var celebrations = CelebrationContributions()
    /// Gates and parameters for Settings ▸ Labs, and which contributions each gate switches. A broken
    /// experiment is listed with its problem rather than failing the plugin.
    var experiments = ExperimentContributions()
    /// Versioned command descriptions. Invalid entries are reported in Command Diagnostics.
    var commandKnowledge: JSONValue?

    init(
        id: String, name: String, version: String? = nil, description: String? = nil, agents: [AgentManifest] = [],
        mcpServers: [MCPServerManifest] = [], workflows: [WorkflowDefinition] = [],
        themes: ThemeContributions = ThemeContributions(), iconSets: IconSetContributions = IconSetContributions(),
        celebrations: CelebrationContributions = CelebrationContributions(),
        experiments: ExperimentContributions = ExperimentContributions()
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.agents = agents
        self.mcpServers = mcpServers
        self.workflows = workflows
        self.themes = themes
        self.iconSets = iconSets
        self.celebrations = celebrations
        self.experiments = experiments
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
        themes = try container.decodeIfPresent(ThemeContributions.self, forKey: .themes) ?? ThemeContributions()
        // Never fail as a whole: each entry decodes or becomes a listed problem.
        iconSets = try container.decodeIfPresent(IconSetContributions.self, forKey: .iconSets) ?? .init()
        celebrations = try container.decodeIfPresent(CelebrationContributions.self, forKey: .celebrations) ?? .init()
        experiments = ExperimentContributions(manifest: decoder)
        commandKnowledge = try container.decodeIfPresent(JSONValue.self, forKey: .commandKnowledge)
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
    /// Declared instruction paths let Settings estimate context without reading file contents.
    var instructionLocations: [TaskInstructionLocation] = []
    /// Where the agent keeps its own MCP configuration ("claude-code", "codex" or "cursor"), so the
    /// MCP feature can show and import the servers it already loads. Nil when unknown.
    var mcpConfig: String?
    /// Native skill delivery supported by this adapter. Nil keeps the MCP fallback.
    var nativeSkill: NativeAgentSkillFormat?
    /// Where the agent's icon comes from. Nil, or nothing found, draws a monogram of its name.
    var icon: AgentIconSource?
    /// Commands besides `command` that must be on the user's PATH for the agent to count as
    /// installed, such as the CLI an adapter drives (`claude` for an `npx` adapter).
    var requires: [String] = []
    /// How to install the agent and sign in, for the Add Agent list and the not-installed state.
    var setup: AgentSetupGuide?
    /// Seconds one of the user's sessions may sit unused before Native closes it, here and in the
    /// agent (`session/close`), and loads it back when it's selected again. For agents that pay for
    /// every open session (a process each) and reopen one faithfully. Nil keeps sessions open.
    var idleSessionTimeout: Int?
    /// Seconds a session may sit with nothing happening before Native's host unloads it from the
    /// agent (`session/close`), keeping its transcript, and resumes it without a replay
    /// (`session/resume`) when it's next used. Once none is loaded, the agent's process ends too.
    /// For agents that keep a lot per loaded session, or that keep things after closing one, and
    /// can resume. Nil keeps sessions loaded.
    var idleUnloadTimeout: Int?
    /// A command that names a session in the agent without asking a model, such as `/rename`. Native
    /// names each session with it ahead of its turns: a new one with its first message (an agent
    /// that titles sessions with a model of its own doesn't then), and any once Native's title for it
    /// differs, so the agent's own session list shows Native's titles. Nil leaves names to the agent.
    var renameCommand: String?
    /// `afterTools` explicitly offers queued steering at tool boundaries without an ACP extension.
    /// `nonInterrupting` permits immediate delivery when the adapter advertises ACP steering.
    var steeringPolicy: SteeringPolicy?
    /// Ways to sign the agent in that it accepts without advertising them, in ACP's shape
    /// (`AuthMethod`): a key in a variable it reads (`"type": "env_var"`), or a device code it
    /// offers only to clients that open links (`"type": "_native/link"`). For hosts nobody sits
    /// at; see docs/agents.md, "Signing in on a host with no screen".
    var authMethods: [AuthMethod] = []
    /// The settings files the agent reads as it starts, which a failed start may show and fix
    /// (Fine print): `~/…`, `$VARIABLE/…` in the agent's environment, or a path in the task's
    /// folder. Native opens no other file an agent's error names.
    var settingsFiles: [String] = []
    /// A declaration for qualification, never a grant supplied to the host. Missing means unsupported.
    var networkCapabilities: AgentNetworkCapabilities?

    init(
        id: String, name: String, symbol: String? = nil, command: String, args: [String] = [],
        env: [String: String] = [:], resolveExecutables: [String: String] = [:], mcpConfig: String? = nil,
        icon: AgentIconSource? = nil, requires: [String] = [], setup: AgentSetupGuide? = nil,
        idleSessionTimeout: Int? = nil, idleUnloadTimeout: Int? = nil, renameCommand: String? = nil,
        steeringPolicy: SteeringPolicy? = nil,
        authMethods: [AuthMethod] = [], instructionLocations: [TaskInstructionLocation] = [],
        settingsFiles: [String] = [], networkCapabilities: AgentNetworkCapabilities? = nil,
        nativeSkill: NativeAgentSkillFormat? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.command = command
        self.args = args
        self.env = env
        self.resolveExecutables = resolveExecutables
        self.mcpConfig = mcpConfig
        self.nativeSkill = nativeSkill
        self.icon = icon
        self.requires = requires
        self.setup = setup
        self.idleSessionTimeout = idleSessionTimeout
        self.idleUnloadTimeout = idleUnloadTimeout
        self.renameCommand = renameCommand
        self.steeringPolicy = steeringPolicy
        self.authMethods = authMethods
        self.instructionLocations = instructionLocations
        self.settingsFiles = settingsFiles
        self.networkCapabilities = networkCapabilities
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
        instructionLocations =
            try container.decodeIfPresent([TaskInstructionLocation].self, forKey: .instructionLocations) ?? []
        mcpConfig = try container.decodeIfPresent(String.self, forKey: .mcpConfig)
        nativeSkill = try container.decodeIfPresent(NativeAgentSkillFormat.self, forKey: .nativeSkill)
        icon = try container.decodeIfPresent(AgentIconSource.self, forKey: .icon)
        requires = try container.decodeIfPresent([String].self, forKey: .requires) ?? []
        setup = try container.decodeIfPresent(AgentSetupGuide.self, forKey: .setup)
        idleSessionTimeout = try container.decodeIfPresent(Int.self, forKey: .idleSessionTimeout)
        idleUnloadTimeout = try container.decodeIfPresent(Int.self, forKey: .idleUnloadTimeout)
        renameCommand = try container.decodeIfPresent(String.self, forKey: .renameCommand)
        steeringPolicy = try container.decodeIfPresent(SteeringPolicy.self, forKey: .steeringPolicy)
        authMethods = try container.decodeIfPresent([AuthMethod].self, forKey: .authMethods) ?? []
        settingsFiles = try container.decodeIfPresent([String].self, forKey: .settingsFiles) ?? []
        networkCapabilities = try container.decodeIfPresent(AgentNetworkCapabilities.self, forKey: .networkCapabilities)
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
        self.init(
            path: try container.decodeIfPresent(String.self, forKey: .path),
            apps: try container.decodeIfPresent([String].self, forKey: .apps) ?? [],
            registry: try container.decodeIfPresent(String.self, forKey: .registry)
        )
    }
}

/// How a user gets an agent going. Native shows these and never runs them.
struct AgentSetupGuide: Codable, Hashable, Sendable {
    /// A command to paste in a terminal that installs the agent without replacing anything else.
    var install: String?
    /// The agent's own install and sign-in docs.
    var docs: URL?
    /// A terminal command that signs in, for agents whose sign-in only works in a terminal. When
    /// set, Sign In runs it in a terminal instead of asking the agent over ACP.
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
    nonisolated struct ID: Hashable, Sendable, Codable, CustomStringConvertible {
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
        // npm would otherwise sit between Native and an npx adapter for as long as it runs.
        return AgentCommand(
            executable: manifest.command,
            arguments: manifest.args,
            environment: environment,
            workingDirectory: URL.homeDirectory
        ).skippingNpx()
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
    /// Something other than an agent's own request is waiting on the user: a workflow's approval
    /// gate, a goal the agent can't continue without them. The session is the task involved, if any.
    case needsUser(SessionContext?, reason: String)
    /// Something stopped short outside a turn: an agent that crashed or couldn't start, a workflow
    /// step or automation run that failed. The session is the task involved, if any.
    case failed(SessionContext?, reason: String)
    /// The agent asked the user something (an `elicitation/create` form). `message` is the question.
    case questionAsked(SessionContext, message: String)
    /// A live context and cost report (not one replayed by `session/load`). Claude Code's
    /// rate-limit status rides on it as `usage.rateLimit`.
    case usageUpdated(SessionContext, Usage)
}

// MARK: - Titles

/// Writes a short title for a session from what the user asked for.
///
/// Tasks in Native's host get their titles there, with no app attached (docs/plugins.md, "Titles
/// with the app closed"). A titler the host runs too names it in `hostProvider`; one that runs
/// only in the app leaves it nil, and the host keeps each task's first message until an app with
/// this titler is attached to write it.
protocol SessionTitler: Sendable {
    /// Returns nil when it can't produce a title right now (for example, no model is available).
    func title(for request: TitleRequest) async throws -> String?
    /// The host's own titler that writes the same titles, if there is one.
    var hostProvider: HostTitleProvider? { get }
}

extension SessionTitler {
    var hostProvider: HostTitleProvider? { nil }
}

struct TitleRequest: Hashable, Sendable {
    var firstTurnOutcome: String? = nil
    var projectName: String
    /// The user's first prompt in the session.
    var prompt: String
    /// The user's own instructions for titles (Settings ▸ AI Instructions), which a titler adds
    /// after its own rules.
    var instructions: AIInstructionAddition?
}

/// Translation is plugin-owned. An absent implementation is unsupported in managed routing.
protocol AgentPrivateRouteTranslator: SessionPolicyTranslator {
    func privateRouteEnvironment(for policy: SessionPolicy, route: AgentPrivateRoute) throws -> [String: String]
}
