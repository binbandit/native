import MCPClient
import SwiftUI

/// A server Native hands agents itself: on/off, what it is, who gets it, how it's doing.
struct MCPManagedServerRow: View {
    let library: MCPLibrary
    let server: ManagedServer
    @Binding var isExpanded: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onCommand: (AgentCLICommand) -> Void

    private var key: MCPServerKey { .managed(server.id) }
    private var isOn: Bool { library.mode(of: server.transport.endpoint.key, in: nil) == .on }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsRow(
                id: MCPServersSettingsPage.rowID(key),
                title: Text(server.name),
                description: Text(server.transport.summary).font(SettingsTextStyle.mono.font),
                detail: Text(detail)
            ) {
                Badge(server.transport.kind.displayName)
                MCPHealthLabel(health: library.health(of: key, inactive: isOn ? nil : "Switched off"))
            } control: {
                HStack(spacing: DS.Space.md) {
                    MCPExpandButton(isExpanded: $isExpanded, name: server.name)
                    Menu {
                        Button("Edit…", action: onEdit)
                        Button("Check") { Task { await library.probe(key) } }
                        Divider()
                        ForEach(library.agents) { agent in
                            if case .success(let command) = AgentCLI.add(
                                server.config(with: library.secrets(for: server.id)), to: agent.format)
                            {
                                Button("Add to \(agent.name)'s Own Config…") { onCommand(command) }
                            }
                        }
                        Divider()
                        Button("Remove", role: .destructive, action: onRemove)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                            .contentShape(.rect)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.ds(.ghost, size: .medium))
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Actions for \(server.name)")
                    SettingsSwitch(
                        server.name,
                        isOn: Binding(
                            get: { isOn },
                            set: { library.setMode($0 ? .on : .off, of: server.transport.endpoint.key, in: nil) }))
                }
            }
            if isExpanded {
                MCPServerDetails(library: library, key: key, name: server.name, project: nil, onCommand: onCommand)
            }
        }
    }

    /// Who gets it, then any agent that doesn't and why.
    private var detail: String {
        let agents: String =
            switch server.agents {
            case .all: "All agents"
            case .only(let ids):
                library.agents.filter { ids.contains($0.id.rawValue) }.map(\.name).joined(separator: ", ")
            }
        let projects: String =
            switch server.projects {
            case .all: "all projects"
            case .only(let paths): paths.map { URL(filePath: $0).lastPathComponent }.joined(separator: ", ")
            }
        var parts = ["\(agents) · \(projects)"]
        parts += library.skippedAgents(for: server).map(\.reason)
        if let cost = library.contextCost(of: server.name) {
            parts.append("\(DSFormat.tokens(cost.tokens)) tokens of Claude Code's context")
        }
        return parts.joined(separator: " · ")
    }
}

/// A server agents load on their own, however many agents and scopes have it.
struct MCPAgentServerRow: View {
    let library: MCPLibrary
    let group: MCPAgentServerGroup
    /// The project the page shows, whose switch the row sets; nil for all projects.
    let project: URL?
    @Binding var isExpanded: Bool
    let onCommand: (AgentCLICommand) -> Void

    private var switchKey: String { group.endpoint.key }
    private var isOn: Bool { library.mode(of: switchKey, in: project) == .on }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsRow(
                id: MCPServersSettingsPage.rowID(group.key),
                title: Text(group.name),
                description: Text(group.primary.server.transport.summary).font(SettingsTextStyle.mono.font),
                detail: Text(detail)
            ) {
                Badge(group.primary.server.transport.kind.displayName)
                MCPHealthLabel(
                    health: library.health(
                        of: group.key,
                        inactive: !isOn ? "Switched off" : group.isLoaded ? nil : group.primary.status.inactiveReason))
                if let cost = library.contextCost(of: group.name) {
                    MCPContextCostLabel(cost: cost)
                }
            } control: {
                HStack(spacing: DS.Space.md) {
                    MCPExpandButton(isExpanded: $isExpanded, name: group.name)
                    MCPAgentServerMenu(library: library, group: group, onCommand: onCommand)
                    SettingsSwitch(
                        group.name,
                        isOn: Binding(
                            get: { isOn }, set: { library.setMode($0 ? .on : .off, of: switchKey, in: project) }))
                }
            }
            if isExpanded {
                MCPServerDetails(
                    library: library, key: group.key, name: group.name, project: group.primary.scope.project,
                    entry: group.primary, onCommand: onCommand)
            }
        }
    }

    /// Which agents load it from where: "Claude Code · User, Codex · User (off)".
    private var detail: String {
        var parts = [
            group.entries.map { entry in
                let location =
                    entry.scope.project.map { "\(entry.scope.displayName) in \($0.lastPathComponent)" }
                    ?? entry.scope.displayName
                let status = entry.status.inactiveReason.map { " (\($0.lowercased()))" } ?? ""
                return "\(entry.format.displayName) · \(location)\(status)"
            }.joined(separator: ", ")
        ]
        if !group.aliases.isEmpty {
            parts.append("Also named " + group.aliases.joined(separator: ", "))
        }
        parts += switchNotes
        if library.managedServer(matching: group.endpoint) != nil {
            parts.append("Also set up in Native")
        }
        let signIn = group.entries.filter {
            library.configuration(of: $0.format)?.signInRequired.contains($0.name) == true
        }
        if !signIn.isEmpty {
            parts.append(signIn.map { "\($0.format.displayName) says it needs sign-in" }.joined(separator: ", "))
        }
        parts += Array(Set(group.entries.flatMap(\.notes))).sorted()
        return parts.joined(separator: " · ")
    }
}

extension MCPAgentServerRow {
    /// How each agent that loads it applies the switch, where that isn't simply per session.
    fileprivate var switchNotes: [String] {
        library.agents.filter { group.formats.contains($0.format) }.compactMap { agent in
            switch library.host?.mcpPolicySupport(for: agent.id) {
            case .perSession?, nil: nil
            case .atLaunch?:
                project == nil
                    ? "\(agent.name) applies the switch when it restarts"
                    : "\(agent.name) can only switch it for all projects"
            case .unsupported(let reason)?: reason
            }
        }
    }
}

/// The actions for an agent's server: import it so every agent gets it, sign in, copy it to
/// another agent, remove it, or show its file. Each change runs the agent's CLI after showing it.
private struct MCPAgentServerMenu: View {
    let library: MCPLibrary
    let group: MCPAgentServerGroup
    let onCommand: (AgentCLICommand) -> Void

    var body: some View {
        Menu {
            Button("Check") { Task { await library.probe(group.key) } }
            if library.managedServer(matching: group.endpoint) == nil {
                Button("Import into Native") { Task { await library.importServer(group.primary) } }
                    .help("Every agent gets it from Native; agents that load it already keep their own.")
            }
            Divider()
            ForEach(group.entries) { entry in
                if case .success(let command) = AgentCLI.signIn(entry) {
                    Button("Sign In with \(entry.format.displayName)…") { onCommand(command) }
                }
            }
            ForEach(missingAgents) { agent in
                if case .success(let command) = AgentCLI.add(group.primary.server, to: agent.format) {
                    Button("Copy to \(agent.name)…") { onCommand(command) }
                }
            }
            Divider()
            ForEach(group.entries) { entry in
                if case .success(let command) = AgentCLI.remove(entry) {
                    Button("Remove from \(entry.format.displayName) (\(entry.scope.displayName))…", role: .destructive)
                    { onCommand(command) }
                }
            }
            if MCPFileActions.canReveal {
                Divider()
                ForEach(Array(Set(group.entries.map(\.source))).sorted { $0.path() < $1.path() }, id: \.self) { file in
                    Button("Show \(file.lastPathComponent)") { MCPFileActions.reveal(file) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.ds(.ghost, size: .medium))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Actions for \(group.name)")
    }

    /// Agents that could load it but don't have it in any scope.
    private var missingAgents: [MCPAgent] {
        library.agents.filter { agent in !group.entries.contains { $0.format == agent.format } }
    }
}

/// The disclosure that opens a row's details, a real button so touch and keyboard reach it.
struct MCPExpandButton: View {
    @Binding var isExpanded: Bool
    let name: String

    var body: some View {
        IconButton(
            isExpanded ? "Hide Details" : "Show Details", systemImage: isExpanded ? "chevron.up" : "chevron.down",
            size: .medium, isActive: isExpanded
        ) {
            withAnimation(.dsDisclosure) { isExpanded.toggle() }
        }
        .accessibilityLabel(isExpanded ? "Hide details for \(name)" : "Show details for \(name)")
    }
}
