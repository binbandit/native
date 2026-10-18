import ACP
import Exec
import Foundation
import MCPClient
import Observation
import os

/// Native's MCP servers: the ones it hands agents itself ("managed": configured once, every agent
/// gets them), the ones each agent loads from its own configuration, and how each is doing. Views,
/// the plugin and other clients go through this model, never to the files, the Keychain or the
/// servers directly.
///
/// Server processes, probes, CLI runs, config files and secrets all belong to the host that owns
/// the projects, so each is reached through a seam (`CommandRunner`, `StdioLauncher`,
/// `ConfigFileSystem`, `SecretStore`) with this Mac's implementation by default.
@Observable
final class MCPLibrary {
    private(set) var servers: [ManagedServer] = []
    /// On/off for every server, Native's and agents', globally and per project.
    private(set) var switches = MCPServerSwitches()
    /// Tools scripts may call without asking, by server switch key: "Always Allow" on the card.
    private(set) var scriptApprovals: [String: Set<String>] = [:]
    /// Each agent's own configuration, as last read.
    private(set) var configurations: [AgentConfigFormat: AgentMCPConfiguration] = [:]
    private(set) var isReadingConfigurations = false
    private(set) var lastRead: Date?
    /// The latest probe of each server, and the ones being probed (set by `probe`).
    var reports: [MCPServerKey: MCPProbeReport] = [:]
    var probing: Set<MCPServerKey> = []
    /// Something that went wrong saving or reading, shown on the page until dismissed.
    var problem: String?
    /// The agent CLI command running now, and how the last one went (set by `run(_:)`).
    var runningCommand: AgentCLICommand?
    var lastCommandRun: MCPCommandRun?

    /// The app, once `MCPServersPlugin.connect` has run.
    @ObservationIgnored var host: (any MCPLibraryHost)?
    @ObservationIgnored let runner: any CommandRunner
    @ObservationIgnored let launcher: any StdioLauncher
    /// Native's connections to servers that run through scripts.
    @ObservationIgnored let scriptConnections: MCPScriptConnections
    /// Whether this build can run scripts at all; without it nothing can run through them.
    var scriptsAvailable = false
    @ObservationIgnored let files: any ConfigFileSystem
    @ObservationIgnored private let secretStore: any SecretStore
    @ObservationIgnored private let storeURL: URL
    /// Secrets read this launch, so the Keychain is asked once per server.
    @ObservationIgnored private var secretCache: [UUID: ManagedServerSecrets] = [:]
    /// Configuration read for folders sessions work in that aren't projects (worktrees,
    /// subfolders), by "format|folder".
    @ObservationIgnored private var folderConfigurations: [String: AgentMCPConfiguration] = [:]
    /// Sessions whose entries are kept, by Native's id for them.
    @ObservationIgnored private var trackedSessions: [UUID: SessionContext] = [:]
    /// What each tracked session has, for views to read without computing.
    private(set) var sessionEntries: [UUID: [MCPSessionEntry]] = [:]
    /// The projects and environment of the last read.
    @ObservationIgnored private var readProjects: Set<String> = []
    @ObservationIgnored private var readEnvironment: [String: String] = [:]
    @ObservationIgnored let logger = Logger(subsystem: "Native", category: "MCP")

    init(
        runner: any CommandRunner = LocalCommandRunner(),
        launcher: any StdioLauncher = LocalStdioLauncher(),
        files: any ConfigFileSystem = LocalConfigFiles(),
        secretStore: any SecretStore = KeychainSecretStore(),
        storeURL: URL = MCPLibrary.defaultStoreURL
    ) {
        self.runner = runner
        self.launcher = launcher
        scriptConnections = MCPScriptConnections(launcher: launcher)
        self.files = files
        self.secretStore = secretStore
        self.storeURL = storeURL
        let stored = load()
        servers = stored.servers
        switches = stored.switches
        scriptApprovals = stored.scriptApprovals
    }

    /// Application Support, per bundle id like the other stores, so dev instances keep their own.
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Native", directoryHint: .isDirectory)
            .appending(path: "mcp-servers.json")
    }

    // MARK: - Managed servers

    func server(_ id: UUID) -> ManagedServer? {
        servers.first { $0.id == id }
    }

    /// Adds or replaces a managed server and its secrets.
    func save(_ server: ManagedServer, secrets: ManagedServerSecrets) {
        do {
            try secretStore.setSecrets(secrets, for: server.id, label: "Native MCP server \(server.name)")
        } catch {
            problem = "Couldn't save \(server.name)'s secrets in the Keychain: \(error.localizedDescription)"
            return
        }
        secretCache[server.id] = secrets
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        reports[.managed(server.id)] = nil
        persist()
        recomputeSessionEntries()
    }

    /// Removes a server; the returned value puts it back exactly (`restore`), secrets included.
    @discardableResult
    func remove(_ id: UUID) -> MCPRemovedServer? {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = MCPRemovedServer(server: servers[index], secrets: secrets(for: id), index: index)
        try? secretStore.setSecrets(ManagedServerSecrets(), for: id, label: removed.server.name)
        secretCache[id] = nil
        servers.remove(at: index)
        reports[.managed(id)] = nil
        persist()
        recomputeSessionEntries()
        return removed
    }

    func restore(_ removed: MCPRemovedServer) {
        guard server(removed.server.id) == nil else { return }
        try? secretStore.setSecrets(
            removed.secrets, for: removed.server.id, label: "Native MCP server \(removed.server.name)")
        secretCache[removed.server.id] = removed.secrets
        servers.insert(removed.server, at: min(removed.index, servers.count))
        persist()
        recomputeSessionEntries()
    }

    // MARK: - Switches

    /// Whether `server` (an `MCPEndpointIdentity.key`) loads in `directory`, or everywhere when nil.
    func mode(of server: String, in directory: URL?) -> MCPServerSwitches.Mode {
        switches.mode(of: server, in: directory)
    }

    /// Sets a server's switch for one project, or all projects when `project` is nil. Nil `mode`
    /// clears a project's switch so it follows the global one. Takes effect at the next session
    /// start; agents that apply it at launch pick it up when they restart.
    func setMode(_ mode: MCPServerSwitches.Mode?, of server: String, in project: URL?) {
        switches.set(mode, for: server, in: project)
        persist()
        recomputeSessionEntries()
        // Agents that apply switches at launch restart for them, but only while idle.
        Task { await host?.mcpApplyLaunchPolicies(force: false) }
        let scripted = scriptedKeys
        Task { await scriptConnections.keep(only: scripted) }
    }

    // MARK: - Script approvals

    func isAlwaysAllowedInScripts(_ tool: String, of server: String) -> Bool {
        scriptApprovals[server]?.contains(tool) == true
    }

    /// Lets scripts call `tool` of `server` (a switch key) without asking again.
    func alwaysAllowInScripts(_ tool: String, of server: String) {
        scriptApprovals[server, default: []].insert(tool)
        persist()
    }

    /// Scripts ask again before calling any of `server`'s tools that can make changes.
    func forgetScriptApprovals(of server: String) {
        scriptApprovals[server] = nil
        persist()
    }

    /// A server's secret values, from the Keychain the first time.
    func secrets(for id: UUID) -> ManagedServerSecrets {
        if let cached = secretCache[id] { return cached }
        do {
            let secrets = try secretStore.secrets(for: id) ?? ManagedServerSecrets()
            secretCache[id] = secrets
            return secrets
        } catch {
            logger.error("Couldn't read secrets for MCP server \(id, privacy: .public): \(error)")
            return ManagedServerSecrets()
        }
    }

    /// Names no managed server may take: other plugins' servers, which every session already has.
    func reservedNames(for session: SessionContext? = nil) -> Set<String> {
        Set((host?.mcpPluginServers(for: session).map(\.name) ?? []) + ["native"])
    }

    // MARK: - Persistence

    /// One small JSON file in Application Support, rewritten on every change. Secrets aren't in it.
    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(MCPStoreFile(servers: servers, switches: switches, scriptApprovals: scriptApprovals))
                .write(to: storeURL, options: .atomic)
        } catch {
            problem = "Couldn't save your MCP servers: \(error.localizedDescription)"
        }
    }

    private func load() -> MCPStoreFile {
        guard let data = try? Data(contentsOf: storeURL) else { return MCPStoreFile() }
        do {
            return try JSONDecoder().decode(MCPStoreFile.self, from: data)
        } catch {
            logger.error("Ignoring unreadable MCP servers file: \(error)")
            problem = "Native couldn't read its saved MCP servers, so it started without them."
            return MCPStoreFile()
        }
    }

    // MARK: - Agents' own configuration

    /// The agents whose own configuration Native can read.
    var agents: [MCPAgent] {
        host?.mcpAgents ?? []
    }

    func configuration(of format: AgentConfigFormat) -> AgentMCPConfiguration? {
        configurations[format]
    }

    /// Reads every agent's configuration again, off the main thread, for every open project and
    /// every folder a tracked session works in, and asks Codex for the servers its plugins add.
    /// Runs at connect, when the app becomes active, and on demand; nothing reads files in `body`.
    func readConfigurations() async {
        guard !isReadingConfigurations, let host else { return }
        isReadingConfigurations = true
        defer { isReadingConfigurations = false }
        let environment = await host.mcpEnvironment()
        let reader = AgentConfigReader(files: files, home: home(in: environment), environment: environment)
        let projects = host.mcpProjects
        let projectKeys = Set(projects.map(ProjectPath.key))
        let folders = Set(trackedSessions.values.map { ProjectPath.key($0.cwd) }).subtracting(projectKeys)
        // Every format, not just running agents': an agent that starts later is covered already.
        var (read, perFolder) = await Task.detached {
            let read = Dictionary(
                uniqueKeysWithValues: AgentConfigFormat.allCases.map { ($0, reader.read($0, projects: projects)) })
            let perFolder = Dictionary(
                uniqueKeysWithValues: folders.flatMap { folder in
                    AgentConfigFormat.allCases.map { format in
                        ("\(format.rawValue)|\(folder)", reader.read(format, projects: [ProjectPath.url(folder)]))
                    }
                })
            return (read, perFolder)
        }.value
        if agents.contains(where: { $0.format == .codex }), let codex = read[.codex],
            let listing = await codexListing(environment: environment)
        {
            read[.codex] = codex.merging(listing)
        }
        configurations = read
        folderConfigurations = perFolder
        readProjects = projectKeys
        readEnvironment = environment
        lastRead = .now
        recomputeSessionEntries()
    }

    /// The first read, on the main thread before agents launch: just the files, for the projects
    /// open, with this process's environment (the shell's isn't known yet).
    func readConfigurationsAtStartup() {
        guard configurations.isEmpty, let host else { return }
        let environment = ProcessInfo.processInfo.environment
        let reader = AgentConfigReader(files: files, home: home(in: environment), environment: environment)
        configurations = Dictionary(
            uniqueKeysWithValues: AgentConfigFormat.allCases.map { ($0, reader.read($0, projects: host.mcpProjects)) })
        readProjects = Set(host.mcpProjects.map(ProjectPath.key))
        readEnvironment = environment
    }

    /// Reads again unless the last read is recent, for when the app comes back to the front.
    func readConfigurationsIfStale() async {
        guard lastRead.map({ Date.now.timeIntervalSince($0) > 10 }) ?? true else { return }
        await readConfigurations()
    }

    /// What `format`'s agent loads in `directory`, from the last read. Never touches files: a
    /// folder that isn't a project is read when a session there is first tracked.
    func agentServers(_ format: AgentConfigFormat, in directory: URL?) -> [ConfiguredServer] {
        guard let configuration = configurations[format] else { return [] }
        guard let directory, let folder = folderConfigurations["\(format.rawValue)|\(ProjectPath.key(directory))"]
        else {
            return configuration.effective(in: directory)
        }
        return folder.withPlugins(of: configuration).effective(in: directory)
    }

    // MARK: - Sessions

    /// The servers each tracked session has, kept up to date as configuration and servers change,
    /// so views read stored values.
    func entries(forSession clientID: UUID) -> [MCPSessionEntry] {
        sessionEntries[clientID] ?? []
    }

    /// Starts keeping a session's entries; reads its folder first if it isn't a project.
    func track(_ session: SessionContext) async {
        trackedSessions[session.clientID] = session
        sessionEntries[session.clientID] = entries(for: session)
        let folder = ProjectPath.key(session.cwd)
        guard !readProjects.contains(folder),
            folderConfigurations["\(AgentConfigFormat.claudeCode.rawValue)|\(folder)"] == nil
        else { return }
        let reader = AgentConfigReader(files: files, home: home(in: readEnvironment), environment: readEnvironment)
        let read = await Task.detached {
            Dictionary(
                uniqueKeysWithValues: AgentConfigFormat.allCases.map { format in
                    ("\(format.rawValue)|\(folder)", reader.read(format, projects: [ProjectPath.url(folder)]))
                })
        }.value
        folderConfigurations.merge(read) { $1 }
        recomputeSessionEntries()
    }

    func untrack(_ clientID: UUID) {
        trackedSessions[clientID] = nil
        sessionEntries[clientID] = nil
    }

    /// In memory only: the configuration and servers are already loaded.
    func recomputeSessionEntries() {
        for (id, session) in trackedSessions {
            let fresh = entries(for: session)
            if sessionEntries[id] != fresh { sessionEntries[id] = fresh }
        }
    }

    private func home(in environment: [String: String]) -> URL {
        environment["HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// `codex mcp list --json`: read-only, and the only way to see what Codex's plugins add.
    private func codexListing(environment: [String: String]) async -> CodexListing? {
        do {
            let result = try await runner.run(
                Command("codex", ["mcp", "list", "--json"], environment: environment, timeout: .seconds(20)))
            guard result.succeeded else { return nil }
            return try CodexListing.decode(result.standardOutput)
        } catch {
            logger.info("No Codex MCP listing: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// A managed server just removed, kept so the removal can be undone.
struct MCPRemovedServer: Hashable {
    let server: ManagedServer
    let secrets: ManagedServerSecrets
    let index: Int
}

/// Which server a probe report belongs to.
enum MCPServerKey: Hashable {
    case managed(UUID)
    /// `ConfiguredServer.id`: the agent, scope and name.
    case agent(String)
    /// Another plugin's server, by name.
    case plugin(String)
}

private extension AgentMCPConfiguration {
    /// Plugin servers apply in every folder; a read of one folder doesn't include what the Codex
    /// listing added, so they're carried over.
    func withPlugins(of full: AgentMCPConfiguration) -> AgentMCPConfiguration {
        var copy = self
        let known = Set(copy.servers.map(\.name))
        copy.servers += full.servers.filter { if case .plugin = $0.scope { !known.contains($0.name) } else { false } }
        copy.signInRequired = full.signInRequired
        return copy
    }
}
