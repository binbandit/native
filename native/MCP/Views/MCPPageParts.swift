import MCPClient
import SwiftUI

/// A one-line notice at the top of the page: something went wrong, or an undo for what just did.
struct MCPNotice: View {
    let text: String
    let tone: Badge.Tone
    var actionTitle: String?
    var action: () -> Void = {}

    private var color: Color {
        switch tone {
        case .danger: .dsDanger
        case .warning: .dsWarning
        default: .dsTextSecondary
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: DS.Space.lg) {
            Text(text)
                .settingsText(.body)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.md)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .transition(.opacity)
    }
}

/// What an empty list is, why, and the one action that fills it. Without an action it's only
/// information, so it's a note rather than a row with nothing to change.
struct MCPEmptyRow: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        if let actionTitle {
            SettingsRow(title, icon: "server.rack", description: Text(message)) {
                Button(actionTitle, action: action)
            }
        } else {
            SettingsNote(title, systemImage: "server.rack") { Text(message) }
        }
    }
}

/// Where each agent keeps its MCP configuration, so the user can find what to edit when the
/// agent has no CLI for a change; plus servers that come with an account instead of a file.
struct MCPConfigFilesFooter: View {
    let library: MCPLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSubheading("Configuration files")
            ForEach(library.agents) { agent in
                if let configuration = library.configuration(of: agent.format) {
                    let files = configuration.files.filter(\.exists)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(agent.name)
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                        if files.isEmpty {
                            Text("No MCP configuration yet.")
                                .settingsText(.caption)
                                .foregroundStyle(.dsTextTertiary)
                        }
                        ForEach(files) { file in
                            fileRow(file)
                        }
                        ForEach(configuration.problems) { problem in
                            Text("\(problem.file.lastPathComponent): \(problem.message)")
                                .settingsText(.caption)
                                .foregroundStyle(.dsDanger)
                        }
                        if !configuration.accountConnectors.isEmpty {
                            Text(
                                "Also connectors from your claude.ai account: \(configuration.accountConnectors.map { $0.replacingOccurrences(of: "claude.ai ", with: "") }.joined(separator: ", ")). Claude Code loads them when you sign in with that account."
                            )
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func fileRow(_ file: ConfigFile) -> some View {
        HStack(spacing: DS.Space.md) {
            Text(file.url.abbreviatedPath)
                .font(SettingsTextStyle.mono.font)
                .foregroundStyle(.dsTextPrimary)
                .textSelection(.enabled)
            Text(file.role)
                .settingsText(.caption)
                .foregroundStyle(.dsTextTertiary)
            Spacer(minLength: DS.Space.md)
            if MCPFileActions.canReveal {
                Button("Show") { MCPFileActions.reveal(file.url) }
                    .buttonStyle(.ds(.ghost, size: .small))
                    .accessibilityLabel("Show \(file.url.lastPathComponent)")
            }
        }
    }
}
