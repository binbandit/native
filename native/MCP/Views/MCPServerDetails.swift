import MCPClient
import SwiftUI

#if DEBUG
#Preview("MCP details - Shared sign-in states") {
    DSPreviewPair { MCPAuthenticationPreview() }
}
#endif

/// A server's details under its row: why it failed (with its own error output) and what to do,
/// why it needs sign-in and how, or who it is and the tools it offers.
struct MCPServerDetails: View {
    let library: MCPLibrary
    let key: MCPServerKey
    let name: String
    /// The project the server's entry belongs to, for "Disable in this project".
    let project: URL?
    /// The agent's entry, for actions that go through the agent.
    var entry: ConfiguredServer?
    let onCommand: (AgentCLICommand) -> Void

    @State private var showsAllTools = false
    private static let toolPreview = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            content
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
    }

    @ViewBuilder
    private var content: some View {
        if library.isProbing(key) {
            HStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .settingUp)
                Text("Connecting to \(name) and listing its tools…")
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
            }
        } else if library.health(of: key) == .signedIn {
            message(
                "Signed in with \(entry?.format.displayName ?? "your agent"). Tasks using this server share that sign-in."
            )
            if let report = library.reports[key], case .needsAuth = report.status {
                message(
                    "Native's separate check has no access to the agent's sign-in credentials, so it couldn't list the tools."
                )
            }
            Button("Check Again") {
                Task {
                    await library.readConfigurations()
                    await library.probe(key)
                }
            }
            .buttonStyle(.ds(.secondary, size: .medium))
        } else if library.health(of: key) == .authenticationUnknown {
            message(
                "\(entry?.format.displayName ?? "Your agent") manages sign-in for this server. Native doesn't read its credentials. Check access in a task with that agent."
            )
            Button("Check Again") {
                Task {
                    await library.readConfigurations()
                    await library.probe(key)
                }
            }
            .buttonStyle(.ds(.secondary, size: .medium))
        } else if let report = library.reports[key] {
            switch report.status {
            case .connected: connected(report)
            case .needsAuth(let challenge): needsAuth(challenge)
            case .failed(let failure): failed(failure, stderr: report.stderr)
            }
        } else {
            if let entry, entry.authentication == .unknown, entry.server.transport.url != nil {
                message("\(entry.format.displayName) manages sign-in. Native hasn't checked this connection.")
            }
            message(
                "Not checked yet. Checking starts the server or reaches it, lists its tools and disconnects; it never calls a tool."
            )
            Button("Check \(name)") { Task { await library.probe(key) } }
                .buttonStyle(.ds(.secondary, size: .medium))
        }
    }

    // MARK: - Connected

    @ViewBuilder
    private func connected(_ report: MCPProbeReport) -> some View {
        let info = report.server
        Text(
            [
                info.map { [$0.title ?? $0.name, $0.version].compactMap(\.self).joined(separator: " ") },
                info.map { "protocol \($0.protocolVersion)" },
                report.transport.map { $0.displayName },
                answeredIn(report.duration),
            ].compactMap(\.self).joined(separator: " · ")
        )
        .settingsText(.caption)
        .foregroundStyle(.dsTextSecondary)
        if let cost = library.contextCost(of: name) {
            MCPContextCostLabel(cost: cost)
        } else if report.toolDefinitionBytes > 0 {
            message(
                "Its tool definitions are \(ByteCountFormatter.string(fromByteCount: Int64(report.toolDefinitionBytes), countStyle: .file)), which agents load into every task's context. Run /context in a Claude Code task to see exactly how many tokens."
            )
        }
        if report.tools.isEmpty {
            message("It offers no tools.")
        } else {
            let tools = report.tools.sorted { $0.definitionBytes > $1.definitionBytes }
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(showsAllTools ? tools : Array(tools.prefix(Self.toolPreview))) { tool in
                    MCPToolRow(
                        tool: tool,
                        share: report.toolDefinitionBytes > 0
                            ? Double(tool.definitionBytes) / Double(report.toolDefinitionBytes) : 0)
                }
            }
            if tools.count > Self.toolPreview {
                Button(showsAllTools ? "Show Fewer" : "Show All \(tools.count) Tools") { showsAllTools.toggle() }
                    .buttonStyle(.ds(.ghost, size: .medium))
            }
        }
    }

    // MARK: - Sign-in

    @ViewBuilder
    private func needsAuth(_ challenge: MCPAuthChallenge) -> some View {
        if challenge.sentCredentials {
            message(
                "\(name) turned down the credentials in its configuration (HTTP \(challenge.statusCode)). Check the token in its headers."
            )
        } else if let entry {
            message(
                "\(entry.format.displayName) has no usable shared sign-in for \(name). Sign in once to use it across tasks."
            )
        } else {
            message(
                "\(name) asks you to sign in (HTTP \(challenge.statusCode)). Agents sign in to servers Native hands them once Native can show their sign-in links; until then, add an API token as an Authorization header."
            )
        }
        HStack(spacing: DS.Space.md) {
            if let entry, case .success(let command) = AgentCLI.signIn(entry) {
                Button("Sign In with \(entry.format.displayName)…") { onCommand(command) }
                    .buttonStyle(.ds(.primary, size: .medium))
            }
            if let resource = challenge.resourceMetadata, let host = resource.host() {
                Text("Signs in through \(host)")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
            }
            Button("Check Again") { Task { await library.probe(key) } }
                .buttonStyle(.ds(.secondary, size: .medium))
        }
    }

    // MARK: - Failure

    @ViewBuilder
    private func failed(_ failure: MCPProbeFailure, stderr: String) -> some View {
        Text(failure.message)
            .settingsText(.body)
            .foregroundStyle(.dsDanger)
            .fixedSize(horizontal: false, vertical: true)
        let output = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Its error output")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
                CappedHeightScrollView(maxHeight: 160) {
                    Text(output)
                        .font(.dsMono)
                        .foregroundStyle(.dsTextSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        HStack(spacing: DS.Space.md) {
            Button("Retry") { Task { await library.probe(key) } }
                .buttonStyle(.ds(.primary, size: .medium))
            if case .managed(let id) = key {
                if let project {
                    Button("Disable in \(project.lastPathComponent)") {
                        library.server(id).map { library.setMode(.off, of: $0.transport.endpoint.key, in: project) }
                    }
                    .buttonStyle(.ds(.secondary, size: .medium))
                }
                Button("Turn Off") {
                    library.server(id).map { library.setMode(.off, of: $0.transport.endpoint.key, in: nil) }
                }
                .buttonStyle(.ds(.secondary, size: .medium))
            } else if let entry, MCPFileActions.canReveal {
                Button("Show \(entry.source.lastPathComponent)") { MCPFileActions.reveal(entry.source) }
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
        }
    }

    /// "answered in 3s", or under a second, which `DSFormat.duration` would round to 0s.
    private func answeredIn(_ duration: Duration) -> String {
        duration < .seconds(1)
            ? "answered in under a second" : "answered in \(DSFormat.duration(Double(duration.components.seconds)))"
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .settingsText(.body)
            .foregroundStyle(.dsTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One tool: its name, what it does, and its share of the server's definitions.
private struct MCPToolRow: View {
    let tool: MCPToolInfo
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.md) {
                Text(tool.name)
                    .font(.dsMono)
                    .foregroundStyle(.dsTextPrimary)
                if tool.isReadOnly == true {
                    Badge("Read-only", tone: .success, style: .soft)
                }
                if tool.isDestructive == true {
                    Badge("Destructive", tone: .danger, style: .soft)
                }
                Spacer(minLength: DS.Space.md)
                if share >= 0.01 {
                    Text(DSFormat.percent(share))
                        .font(.dsCaption)
                        .monospacedDigit()
                        .foregroundStyle(.dsTextTertiary)
                        .help("Share of this server's tool definitions")
                }
            }
            if let description = tool.description, !description.isEmpty {
                Text(description)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
