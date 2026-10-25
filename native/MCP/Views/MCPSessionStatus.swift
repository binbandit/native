import MCPClient
import SwiftUI

#if DEBUG
#Preview("MCP task - Shared sign-in") {
    let app = AppModel.preview()
    if let session = SessionModel.preview(in: app, agent: "codex") {
        DSPreviewPair {
            MCPSessionPanel(
                library: MCPAuthenticationPreviewFixtures.library(.signedIn), session: session,
                entries: [.agent(MCPAuthenticationPreviewFixtures.entry(.signedIn))])
        }
    }
}
#endif

extension FocusedValues {
    /// The focused session's MCP list, for View ▸ Show MCP Servers (⌃⌘M).
    @Entry var mcpServersPopover: Binding<Bool>?
}

extension EnvironmentValues {
    /// Whether the session's MCP list is showing, owned by the session view (`mcpServersPresentation`)
    /// so ⌃⌘M reaches whichever arrangement of the composer's controls is on screen.
    @Entry var mcpServersPopover: Binding<Bool>?
}

extension View {
    /// Owns whether this session's MCP list is showing, for the composer's MCP chip and ⌃⌘M.
    func mcpServersPresentation() -> some View {
        modifier(MCPServersPresentation())
    }
}

private struct MCPServersPresentation: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content.environment(\.mcpServersPopover, $isPresented)
    }
}

/// A session's MCP servers in the composer's trailing cluster, beside the context ring: a server
/// glyph and how many are on, with a warning dot only when one failed or needs sign-in. It stays
/// quiet (absent) when the session has none. Click, or ⌃⌘M, for the list above it.
struct MCPComposerChip: View {
    let session: SessionModel
    /// The count beside the glyph; the composer's tighter densities show the glyph alone.
    var showsCount = true

    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.mcpServersPopover) private var sharedPresentation
    @State private var ownPresentation = false
    @State private var isHovered = false

    private var isPresented: Binding<Bool> {
        sharedPresentation ?? $ownPresentation
    }

    var body: some View {
        if let library = MCPServersPlugin.library(in: model.plugins) {
            // A real container, so tracking starts even while there's nothing to show.
            HStack(spacing: 0) {
                chip(library)
            }
            .task(id: session.clientID) { await library.track(session.context) }
        }
    }

    @ViewBuilder
    private func chip(_ library: MCPLibrary) -> some View {
        // Stored values only: the library keeps them current, so streaming updates cost nothing here.
        let entries = library.entries(forSession: session.clientID)
        let summary = MCPSessionSummary(library: library, entries: entries)
        if !entries.isEmpty {
            Button {
                isPresented.wrappedValue.toggle()
            } label: {
                label(summary)
            }
            .buttonStyle(.plain)
            .help(CommandRegistry.shared.help(summary.help, for: .viewMCPServers))
            .accessibilityLabel("MCP servers")
            .accessibilityValue(summary.help)
            .focusedSceneValue(\.mcpServersPopover, isPresented)
            .popover(isPresented: isPresented, arrowEdge: .top) {
                MCPSessionPanel(
                    library: library, session: session, entries: entries,
                    onManage: {
                        isPresented.wrappedValue = false
                        settings.open(.mcpServers)
                    }
                )
                .dsPopoverBackground()
            }
        }
    }

    /// Drawn like the context indicator beside it: no outline, a wash on hover and while open.
    private func label(_ summary: MCPSessionSummary) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        let isOpen = isPresented.wrappedValue
        return HStack(spacing: DS.Space.sm) {
            // The dot rides the glyph's corner, so it reads the same with or without the count.
            PillIcon("server.rack")
                .overlay(alignment: .topTrailing) {
                    if summary.attention > 0 {
                        StatusDot(color: .dsWarning)
                            .offset(x: MCPChipMetrics.dotOffset, y: -MCPChipMetrics.dotOffset)
                    }
                }
            if showsCount {
                Text("\(summary.active)")
                    .monospacedDigit()
            }
        }
        .font(.dsBody)
        .foregroundStyle(isHovered || isOpen ? .dsTextPrimary : .dsTextSecondary)
        .padding(.horizontal, DS.Space.sm)
        .frame(minWidth: DS.Size.composerPill, minHeight: DS.Size.composerPill)
        .background(isOpen ? Color.dsSelected : isHovered ? .dsHover : .clear, in: shape)
        .contentShape(shape)
        .trackHover($isHovered)
    }
}

private enum MCPChipMetrics {
    /// The warning dot sits on the glyph's top-right corner.
    static let dotOffset: CGFloat = 3
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
            ? "This task has no MCP servers."
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
    /// A page in Task Settings, whose first line already names it: no title bar, at its width.
    var isPage = false

    @State private var pendingCommand: AgentCLICommand?
    @State private var note: String?

    var body: some View {
        Group {
            if isPage {
                list.frame(width: DS.ComposerSettings.popoverWidth)
            } else {
                PopoverPanel(title: "MCP Servers", systemImage: "server.rack") {
                    Text(session.cwd.lastPathComponent)
                } content: {
                    list
                }
            }
        }
        .task {
            await library.readConfigurationsIfStale()
            await library.probeStale(library.entries(forSession: session.clientID), in: session.context)
        }
        .sheet(item: $pendingCommand) { command in
            MCPCommandSheet(library: library, command: command, task: session)
        }
    }

    private var list: some View {
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
                Text("Switches apply to the next task in this folder.")
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
                if let key = entry.switchKey {
                    let lock = library.organizationLock(for: entry)
                    // For the next session here: this one keeps what it started with.
                    SettingsSwitch(
                        "\(entry.name) in \(session.cwd.lastPathComponent)",
                        isOn: Binding(
                            get: { lock == nil && library.mode(of: key, in: session.cwd) != .off },
                            set: { library.setMode($0 ? .on : .off, of: key, in: session.cwd) })
                    )
                    .disabled(lock != nil)
                    .help(lock ?? "Switch \(entry.name) for new tasks in \(session.cwd.lastPathComponent)")
                }
            }
            if let lock = library.organizationLock(for: entry) {
                Label(lock, systemImage: "lock")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            if let cost = library.contextCost(of: entry.name, in: session.key) {
                MCPContextCostLabel(cost: cost)
            } else if entry.isActive, library.isLoaded(entry.name, in: session.key) == false {
                Text("Not in this task's context: \(session.agentName) didn't load it.")
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
                        "Runs /mcp disable \(configured.name) in this task; Claude Code remembers it for the project."
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
