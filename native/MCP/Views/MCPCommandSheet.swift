import MCPClient
import SwiftUI

/// Shows the exact agent CLI command a change runs, runs it when asked, then shows what happened.
/// Native never edits an agent's configuration any other way.
struct MCPCommandSheet: View {
    let library: MCPLibrary
    let command: AgentCLICommand

    @Environment(\.dismiss) private var dismiss
    @State private var run: MCPCommandRun?

    private var isRunning: Bool { library.runningCommand == command }

    private var title: String {
        switch command.action {
        case .add: "Add \(command.serverName) to \(command.format.displayName)"
        case .remove: "Remove \(command.serverName) from \(command.format.displayName)"
        case .signIn: "Sign in to \(command.serverName)"
        }
    }

    private var explanation: String {
        switch command.action {
        case .add:
            "\(command.format.displayName) saves it in its own configuration, so it loads the server outside Native too."
        case .remove:
            "\(command.format.displayName) stops loading it in new sessions. Native's own copy, if you set one up, isn't affected."
        case .signIn:
            "\(command.format.displayName) opens your browser to sign in and keeps the token itself. Come back here when the page says you're done."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text(title)
                    .settingsText(.title)
                    .foregroundStyle(.dsTextPrimary)
                Text(explanation)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("The command Native runs")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
                Text(command.displayText)
                    .font(.dsMono)
                    .foregroundStyle(.dsTextPrimary)
                    .textSelection(.enabled)
                    .padding(DS.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
            }
            if isRunning {
                HStack(spacing: DS.Space.md) {
                    DotGridLoader(pattern: .settingUp)
                    Text(command.action == .signIn ? "Waiting for you to finish signing in…" : "Running…")
                        .settingsText(.body)
                        .foregroundStyle(.dsTextSecondary)
                }
            } else if let run {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(
                        run.succeeded
                            ? "Done. Native read \(command.format.displayName)'s configuration again."
                            : "It didn't work. \(command.format.displayName) said:"
                    )
                    .settingsText(.body)
                    .foregroundStyle(run.succeeded ? .dsSuccess : .dsDanger)
                    if !run.output.isEmpty {
                        CappedHeightScrollView(maxHeight: 160) {
                            Text(run.output)
                                .font(.dsMono)
                                .foregroundStyle(.dsTextSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            HStack(spacing: DS.Space.md) {
                Spacer()
                if run?.succeeded == true {
                    Button("Done") { dismiss() }
                        .buttonStyle(.ds(.primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.ds(.secondary, size: .large))
                        .keyboardShortcut(.cancelAction)
                    Button(run == nil ? "Run" : "Try Again") {
                        Task { run = await library.run(command) }
                    }
                    .buttonStyle(.ds(command.action == .remove ? .destructive : .primary, size: .large))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning)
                }
            }
        }
        .padding(DS.Space.xxl)
        .frame(width: 560)
        .background(.dsBackground)
    }
}
