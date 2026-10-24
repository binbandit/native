import MCPClient
import SwiftUI
import Undo

extension SettingsPane.ID {
    static let mcpServers = Self("mcp-servers")
}

extension SettingsPane {
    /// Settings ▸ MCP Servers: the servers Native gives every agent, and the ones each agent loads
    /// on its own.
    static func mcpServers(registry: PluginRegistry) -> SettingsPane {
        SettingsPane(
            id: .mcpServers,
            title: "MCP Servers",
            systemImage: "server.rack",
            group: .extensions,
            order: 20,
            keywords: ["mcp", "tools", "context", "oauth", "sign in", ".mcp.json", "config.toml", "mcp.json"],
            searchEntries: {
                guard let library = MCPServersPlugin.library(in: registry) else { return [] }
                return library.servers.map {
                    SettingsSearchEntry(
                        id: MCPServersSettingsPage.rowID(.managed($0.id)), title: $0.name,
                        description: $0.transport.summary)
                }
                    + library.agentServerGroups(in: nil).map {
                        SettingsSearchEntry(
                            id: MCPServersSettingsPage.rowID($0.key), title: $0.name,
                            description: $0.primary.server.transport.summary)
                    }
            },
            content: { MCPServersSettingsPage() }
        )
    }
}

/// What the editor sheet is editing.
enum MCPEditorTarget: Identifiable, Hashable {
    case new
    case edit(UUID)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let id): id.uuidString
        }
    }
}

struct MCPServersSettingsPage: View {
    @Environment(PluginRegistry.self) private var registry
    @Environment(SettingsPresentation.self) private var presentation
    @Environment(\.undoManager) private var undoManager
    @State private var editing: MCPEditorTarget?
    @State private var pendingCommand: AgentCLICommand?
    /// The project whose servers are shown, by path; empty for every scope at once.
    @State private var projectPath = ""
    @State private var removed: MCPRemovedServer?
    @State private var expanded: Set<MCPServerKey> = []

    static func rowID(_ key: MCPServerKey) -> SettingsRowID {
        switch key {
        case .managed(let id): SettingsRowID("mcp.managed.\(id.uuidString)")
        case .agent(let id): SettingsRowID("mcp.agent.\(id)")
        case .plugin(let id): SettingsRowID("mcp.plugin.\(id)")
        }
    }

    var body: some View {
        if let library = MCPServersPlugin.library(in: registry) {
            page(library)
        } else {
            EmptyStateView(
                "MCP servers aren't available", systemImage: "server.rack",
                message: "The MCP Servers plugin isn't loaded in this build.")
        }
    }

    private func page(_ library: MCPLibrary) -> some View {
        SettingsPage {
            SettingsHeader(
                title: "MCP Servers",
                description: Text(
                    "Servers give agents tools. Set one up here once and every agent gets it in every task. Agents also load servers from their own configuration, listed below; Native doesn't hand them a second copy."
                ),
                plainly: .init(
                    title: "MCP Servers",
                    description: "Tools for your agents. Set a server up here and every agent gets it.")
            ) {
                Button("Check All", systemImage: "stethoscope") { Task { await library.probeAll() } }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .help("Start or reach every server, list its tools and disconnect. No tool is called.")
                Button("Add Server", systemImage: "plus") { editing = .new }
                    .buttonStyle(.ds(.primary, size: .medium))
            }
            if !registry.isEnabled(MCPServersPlugin.id) {
                MCPNotice(
                    text:
                        "The MCP Servers plugin is off, so agents don't get the servers set up here. Turn it on in Settings ▸ Extensions.",
                    tone: .warning)
            }
            if let problem = library.problem {
                MCPNotice(text: problem, tone: .danger, actionTitle: "Dismiss") { library.problem = nil }
            }
            let waiting = library.host?.mcpAgentsAwaitingRestart ?? []
            if !waiting.isEmpty {
                MCPNotice(
                    text:
                        "\(waiting.map(\.name).joined(separator: " and ")) still starts tasks with the old switches. It restarts to pick them up as soon as none of its tasks is working.",
                    tone: .neutral, actionTitle: "Apply to Running Tasks"
                ) {
                    Task { await library.host?.mcpApplyLaunchPolicies(force: true) }
                }
            }
            if let removed {
                MCPNotice(text: "Removed \(removed.server.name).", tone: .neutral, actionTitle: "Undo") {
                    undo(removed, in: library)
                }
            }
            managedSection(library)
            agentsSection(library)
        }
        .task { if library.lastRead == nil { await library.readConfigurations() } }
        // A project's settings link here to show its switches.
        .onAppear { takeScope() }
        .onChange(of: presentation.projectScope) { takeScope() }
        .sheet(item: $editing) { target in
            MCPServerEditor(library: library, target: target)
        }
        .sheet(item: $pendingCommand) { command in
            MCPCommandSheet(library: library, command: command)
        }
    }

    // MARK: - Native's servers

    private func takeScope() {
        if let project = presentation.takeProjectScope(for: .mcpServers) { projectPath = ProjectPath.key(project) }
    }

    private func managedSection(_ library: MCPLibrary) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(
                "Set up in Native",
                note: "Handed to the agents and projects you choose, in every task they start or reopen.",
                plainly: .init(title: "Shared with every agent", description: "Choose agents and projects per server."))
            if library.servers.isEmpty {
                MCPEmptyRow(
                    title: "No servers yet",
                    message: "Add one, or import a server an agent already uses so every agent gets it.",
                    actionTitle: "Add Server"
                ) { editing = .new }
            } else {
                SettingsRowGroup {
                    ForEach(library.servers) { server in
                        MCPManagedServerRow(
                            library: library,
                            server: server,
                            isExpanded: binding(for: .managed(server.id)),
                            onEdit: { editing = .edit(server.id) },
                            onRemove: { remove(server.id, from: library) },
                            onCommand: { pendingCommand = $0 }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Agents' own servers

    private func agentsSection(_ library: MCPLibrary) -> some View {
        let project = projectPath.isEmpty ? nil : ProjectPath.url(projectPath)
        let groups = library.agentServerGroups(in: project)
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                SettingsSubheading(
                    "Loaded by your agents",
                    note:
                        "From each agent's own configuration. Changes go through the agent's CLI, never by editing its files.",
                    plainly: .init(
                        title: "Loaded by agents themselves",
                        description: "From each agent's own config. Native changes them only through the agent's CLI.")
                )
                Spacer(minLength: DS.Space.xl)
                SettingsSelect(label: "Project", selection: $projectPath, options: projectOptions(library), width: 180)
                IconButton("Read Again", systemImage: "arrow.clockwise") { Task { await library.readConfigurations() } }
                    .disabled(library.isReadingConfigurations)
                    .help("Read every agent's MCP configuration again")
            }
            if library.agents.isEmpty {
                MCPEmptyRow(
                    title: "No agents with MCP settings",
                    message:
                        "Claude Code, Codex and Cursor keep their own MCP servers; turn one on in Agents to see what it loads."
                )
            } else if groups.isEmpty {
                MCPEmptyRow(
                    title: library.isReadingConfigurations
                        ? "Reading your agents' configuration…" : "Your agents load no servers of their own",
                    message: project == nil
                        ? "Servers you add with an agent's CLI, or in its config file, show here."
                        : "Nothing in this project. Choose All Projects to see every scope."
                )
            } else {
                SettingsRowGroup {
                    ForEach(groups) { group in
                        MCPAgentServerRow(
                            library: library,
                            group: group,
                            project: project,
                            isExpanded: binding(for: group.key),
                            onCommand: { pendingCommand = $0 }
                        )
                    }
                }
            }
            MCPConfigFoldersSection(library: library, project: project)
        }
    }

    private func projectOptions(_ library: MCPLibrary) -> [SettingsSelect<String>.Option] {
        [SettingsSelect<String>.Option(value: "", title: "All Projects")]
            + (library.host?.mcpProjects ?? []).map {
                SettingsSelect<String>.Option(value: ProjectPath.key($0), title: $0.lastPathComponent)
            }
    }

    private func binding(for key: MCPServerKey) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) }, set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } })
    }

    // MARK: - Undo

    private func remove(_ id: UUID, from library: MCPLibrary) {
        guard let removed = library.remove(id) else { return }
        withAnimation(.dsStandard) { self.removed = removed }
        undoManager?.registerUndo(withTarget: library) { library in
            library.restore(removed)
        }
        undoManager?.setActionName("Remove \(removed.server.name)")
    }

    private func undo(_ removed: MCPRemovedServer, in library: MCPLibrary) {
        library.restore(removed)
        undoManager?.removeActions(withTarget: library)
        withAnimation(.dsStandard) { self.removed = nil }
    }
}
