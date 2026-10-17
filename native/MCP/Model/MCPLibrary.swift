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
    @ObservationIgnored let files: any ConfigFileSystem
    @ObservationIgnored private let secretStore: any SecretStore
    @ObservationIgnored private let storeURL: URL
    /// Secrets read this launch, so the Keychain is asked once per server.
    @ObservationIgnored private var secretCache: [UUID: ManagedServerSecrets] = [:]
    /// Agents' effective servers in folders that aren't projects (worktrees, subfolders).
    @ObservationIgnored private var directoryCache: [String: [ConfiguredServer]] = [:]
    /// The projects and environment of the last read.
    @ObservationIgnored private var readProjects: Set<String> = []
    @ObservationIgnored private var readEnvironment: [String: String] = [:]
    @ObservationIgnored let logger = Logger(subsystem: "Native", category: "MCP")

    init(
        runner: any CommandRunner = LocalCommandRunner(),
        launcher: any StdioLauncher = LocalStdioLauncher(),
        files: any ConfigFileSystem = LocalConfigFiles(),
        secretStore: any SecretStore = KeychainSecretStore(),
        storeURL: URL = URL.applicationSupportDirectory.appending(path: "Native/mcp-servers.json", directoryHint: .notDirectory)
    ) {
        self.runner = runner
        self.launcher = launcher
        self.files = files
        self.secretStore = secretStore
        self.storeURL = storeURL
        servers = load()
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
        return removed
    }

    func restore(_ removed: MCPRemovedServer) {
        guard server(removed.server.id) == nil else { return }
        try? secretStore.setSecrets(removed.secrets, for: removed.server.id, label: "Native MCP server \(removed.server.name)")
        secretCache[removed.server.id] = removed.secrets
        servers.insert(removed.server, at: min(removed.index, servers.count))
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        update(id) { $0.isEnabled = isEnabled }
    }

    /// Turns a server off in one project only, keeping it everywhere else.
    func disable(_ id: UUID, in project: URL) {
        update(id) { server in
            let path = ProjectPath.key(project)
            if !server.excludedProjects.contains(path) { server.excludedProjects.append(path) }
        }
    }

    func enable(_ id: UUID, in project: URL) {
        update(id) { $0.excludedProjects.removeAll { $0 == ProjectPath.key(project) } }
    }

    private func update(_ id: UUID, _ change: (inout ManagedServer) -> Void) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        change(&servers[index])
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
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(servers).write(to: storeURL, options: .atomic)
        } catch {
            problem = "Couldn't save your MCP servers: \(error.localizedDescription)"
        }
    }

    private func load() -> [ManagedServer] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        do {
            return try JSONDecoder().decode([ManagedServer].self, from: data)
        } catch {
            logger.error("Ignoring unreadable MCP servers file: \(error)")
            problem = "Native couldn't read its saved MCP servers, so it started without them."
            return []
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

    /// Reads every agent's configuration again, for every open project, and asks Codex for the
    /// servers its plugins add.
    func readConfigurations() async {
        guard !isReadingConfigurations, let host else { return }
        isReadingConfigurations = true
        defer { isReadingConfigurations = false }
        let environment = await host.mcpEnvironment()
        let reader = AgentConfigReader(files: files, home: home(in: environment), environment: environment)
        let projects = host.mcpProjects
        let formats = Set(agents.map(\.format))
        var read = await Task.detached {
            Dictionary(uniqueKeysWithValues: formats.map { ($0, reader.read($0, projects: projects)) })
        }.value
        if formats.contains(.codex), let codex = read[.codex], let listing = await codexListing(environment: environment) {
            read[.codex] = codex.merging(listing)
        }
        configurations = read
        directoryCache = [:]
        readProjects = Set(projects.map(ProjectPath.key))
        readEnvironment = environment
        lastRead = .now
    }

    /// What `format`'s agent loads in `directory`. Projects come from the last read; other folders
    /// (worktrees, subfolders) are read once and kept until the next.
    func agentServers(_ format: AgentConfigFormat, in directory: URL?) -> [ConfiguredServer] {
        guard let configuration = configurations[format] else { return [] }
        guard let directory, !readProjects.contains(ProjectPath.key(directory)) else { return configuration.effective(in: directory) }
        let key = "\(format.rawValue)|\(ProjectPath.key(directory))"
        if let cached = directoryCache[key] { return cached }
        let fresh = AgentConfigReader(files: files, home: home(in: readEnvironment), environment: readEnvironment).read(format, projects: [directory])
        let servers = fresh.withPlugins(of: configuration).effective(in: directory)
        directoryCache[key] = servers
        return servers
    }

    private func home(in environment: [String: String]) -> URL {
        environment["HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) } ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// `codex mcp list --json`: read-only, and the only way to see what Codex's plugins add.
    private func codexListing(environment: [String: String]) async -> CodexListing? {
        do {
            let result = try await runner.run(Command("codex", ["mcp", "list", "--json"], environment: environment, timeout: .seconds(20)))
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
