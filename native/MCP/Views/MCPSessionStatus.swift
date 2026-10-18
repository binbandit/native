import MCPClient
import SwiftUI

extension FocusedValues {
    /// The focused session's MCP list, for View ▸ Show MCP Servers (⌃⌘M).
    @Entry var mcpServersPopover: Binding<Bool>?
}

/// A session's MCP servers at a glance, for the session header: how many it has and whether any
/// needs attention. Click (or ⌃⌘M) for the list.
struct MCPSessionStatusButton: View {
    let session: SessionModel
    /// Opens Settings ▸ MCP Servers.
    var onManage: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var isPresented = false

    var body: some View {
        if let library = MCPServersPlugin.library(in: model.plugins) {
            // A real container, so tracking starts even while there's nothing to show.
            HStack(spacing: 0) {
                button(library)
            }
            .task(id: session.clientID) { await library.track(session.context) }
        }
    }

    @ViewBuilder
    private func button(_ library: MCPLibrary) -> some View {
        do {
            // Stored values only: the library keeps them current, so streaming updates cost nothing here.
            let entries = library.entries(forSession: session.clientID)
            let summary = MCPSessionSummary(library: library, entries: entries)
            // Quiet when the session has no servers at all.
            if !entries.isEmpty {
                Button {
                    isPresented.toggle()
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "server.rack")
                        Text("\(summary.active)")
                            .monospacedDigit()
                        if summary.attention > 0 {
                            StatusDot(color: .dsDanger)
                        }
                    }
                }
                .help(summary.help + " (⌃⌘M)")
                .accessibilityLabel("MCP servers")
                .accessibilityValue(summary.help)
                .focusedSceneValue(\.mcpServersPopover, $isPresented)
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    MCPSessionPanel(
                        library: library, session: session, entries: entries,
                        onManage: onManage.map { manage in
                            {
                                isPresented = false; manage()
                            }
                        }
                    )
                    .presentationBackground(.dsOverlay)
                }
            }
        }
    }
}

/// Counts for the button's label and tooltip.
struct MCPSessionSummary {
    let active: Int
    let attention: Int
    let help: String

    init(library: MCPLibrary, entries: [MCPSessionEntry]) {
        let activeEntries = entries.filter(\.isActive)
        active = activeEntries.count
        attention = activeEntries.count { library.health(of: $0.key).needsAttention }
        help =
            active == 0
            ? "This session has no MCP servers."
            : "\(active) MCP \(active == 1 ? "server" : "servers")"
                + (attention > 0 ? ", \(attention) need attention" : "") + ". Click to see them."
    }
}

/// The servers a session has, where each comes from, how it's doing and what it costs, with the
/// way out when one fails.
struct MCPSessionPanel: View {
    let library: MCPLibrary
    let session: SessionModel
    let entries: [MCPSessionEntry]
    var onManage: (() -> Void)?

    @State private var pendingCommand: AgentCLICommand?
    @State private var note: String?

    var body: some View {
        StatusBarPanel(title: "MCP Servers", systemImage: "server.rack") {
            Text(session.cwd.lastPathComponent)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    EmptyStateView(
                        "No MCP servers", systemImage: "server.rack",
                        message: "\(session.agentName) loads none here, and none are set up in Native."
                    ) {
                        if let onManage {
                            Button("Add a Server…", action: onManage)
                                .buttonStyle(.ds(.secondary, size: .medium))
                        }
                    }
                    .padding(DS.Space.lg)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                row(entry)
                            }
                        }
                        .padding(DS.Space.xs)
                    }
                    .frame(maxHeight: StatusBarMetrics.panelListHeight)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let note {
                    Text(note)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .padding(.horizontal, DS.Space.lg)
                        .padding(.vertical, DS.Space.sm)
                }
                SeparatorLine()
                HStack {
                    Text("Changes apply to sessions started or reopened after them.")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                    Spacer(minLength: DS.Space.md)
                    if let onManage {
                        Button("Manage…", action: onManage)
                            .buttonStyle(.ds(.ghost, size: .small))
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.sm)
            }
        }
        .task { await library.probeStale(entries, in: session.context) }
        .sheet(item: $pendingCommand) { command in
            MCPCommandSheet(library: library, command: command)
        }
    }

    @ViewBuilder
    private func row(_ entry: MCPSessionEntry) -> some View {
        let health = library.health(of: entry.key, inactive: inactiveReason(entry))
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.md) {
                Text(entry.name)
                    .font(.dsBodyMedium)
                    .foregroundStyle(entry.isActive ? .dsTextPrimary : .dsTextTertiary)
                Text(entry.origin)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                Spacer(minLength: DS.Space.md)
                MCPHealthLabel(health: health)
            }
            if let cost = library.contextCost(of: entry.name, in: session.key) {
                MCPContextCostLabel(cost: cost)
            } else if entry.isActive, library.isLoaded(entry.name, in: session.key) == false {
                Text("Not in this session's context: \(session.agentName) didn't load it.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsWarning)
            }
            if health.needsAttention {
                actions(for: entry, health: health)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .accessibilityElement(children: .contain)
    }

    private func inactiveReason(_ entry: MCPSessionEntry) -> String? {
        switch entry {
        case .agent(let configured): configured.status.inactiveReason
        case .managed(_, let outcome): outcome.inactiveReason(agentName: session.agentName)
        case .plugin: nil
        }
    }

    /// Retry, and the way to stop it failing here: off in this project, or sign in.
    @ViewBuilder
    private func actions(for entry: MCPSessionEntry, health: MCPHealth) -> some View {
        HStack(spacing: DS.Space.sm) {
            Button("Retry") { Task { await library.probe(entry.key, in: session.context) } }
                .buttonStyle(.ds(.secondary, size: .small))
            switch entry {
            case .managed(let server, _):
                Button("Disable in \(session.cwd.lastPathComponent)") {
                    library.setMode(.off, of: server.transport.endpoint.key, in: session.cwd)
                }
                .buttonStyle(.ds(.ghost, size: .small))
            case .agent(let configured):
                if case .needsAuth = health, case .success(let command) = AgentCLI.signIn(configured) {
                    Button("Sign In with \(configured.format.displayName)…") { pendingCommand = command }
                        .buttonStyle(.ds(.ghost, size: .small))
                }
                if configured.format == .claudeCode {
                    // Claude Code's own per-project switch, remembered in its configuration.
                    Button("Disable in \(session.cwd.lastPathComponent)") {
                        Task { await disableInClaude(configured.name) }
                    }
                    .buttonStyle(.ds(.ghost, size: .small))
                    .help(
                        "Runs /mcp disable \(configured.name) in this session; Claude Code remembers it for the project."
                    )
                }
            case .plugin:
                EmptyView()
            }
        }
        if case .failed(let failure) = health {
            Text(failure.message)
                .font(.dsCaption)
                .foregroundStyle(.dsDanger)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func disableInClaude(_ name: String) async {
        do {
            let reply = try await session.runHiddenCommand("/mcp disable \(name)")
            note =
                reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Claude Code turned \(name) off in this project." : reply
            await library.readConfigurations()
        } catch {
            note = "Couldn't ask Claude Code: \(error.localizedDescription)"
        }
    }
}
