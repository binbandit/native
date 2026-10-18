import SwiftUI
import Terminal

/// Signs in to an agent in a terminal, for agents that can only sign in there: runs the agent's
/// own sign-in command, and when it succeeds restarts the agent so it picks up the login and
/// carries on with what the user was doing. A failed sign-in keeps its output on screen with Try
/// Again. Closing the sheet ends the command.
struct AgentTerminalSignInSheet: View {
    let request: AgentTerminalSignIn
    /// Restarts the agent with the new login and carries on (`AppModel.finishTerminalSignIn`).
    let finish: (AgentTerminalSignIn) async -> Void

    @Environment(TerminalStore.self) private var terminals
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsAccentPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var run: AgentTerminalSignInRun?
    @State private var isFinishing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            SeparatorLine()
            terminal
                .frame(height: 340)
                .background(.dsSurfaceSunken)
            SeparatorLine()
            footer
        }
        .frame(width: 680)
        .background(.dsBackground)
        .onAppear(perform: start)
        .onDisappear { run?.end() }
        .onChange(of: run?.outcome) { _, outcome in
            if outcome == .succeeded {
                complete()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            AgentIcon(agent: request.agent, size: DS.Size.controlXS)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Sign In to \(request.agent.displayName)")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                Text(
                    "\(request.agent.displayName) signs in from a terminal. Follow its steps below; Native checks again when it finishes."
                )
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.xl)
    }

    @ViewBuilder private var terminal: some View {
        switch terminals.availability {
        case .available:
            if let run, let surface = run.surface {
                #if os(macOS)
                TerminalSurfaceHost(surface: surface)
                    .overlay(alignment: .bottom) { outcome.padding(DS.Space.md) }
                #endif
            } else if case .failed = run?.outcome {
                // The terminal never started, or the user closed it after a failed sign-in.
                failure
            }
        case .notBuilt, .failed:
            // No terminal in this build: the command is still the way in, from the user's own.
            EmptyStateView(
                "Sign in from your terminal",
                systemImage: "terminal",
                message: "Run this in Terminal, then choose Check Again."
            ) {
                AgentSetupCommand(command: request.command)
                    .frame(maxWidth: 420)
            }
        }
    }

    /// Over the command's last output once it ends with an error.
    @ViewBuilder private var outcome: some View {
        if case .failed(let code) = run?.outcome {
            ErrorState(
                "Signing in didn't finish",
                suggestion: [
                    code.map { "“\(request.command)” exited with code \($0)." },
                    "Its output is above; fix what it reported, then try again.",
                ]
                .compactMap(\.self).joined(separator: " "),
                primary: .init("Try Again") { run?.restart() }
            )
        }
    }

    private var failure: some View {
        ErrorState(
            "Signing in didn't finish",
            suggestion: "Try again here, or run “\(request.command)” in your own terminal and choose Check Again.",
            primary: .init("Try Again") { run?.restart() },
            layout: .pane
        )
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            Text(request.command)
                .font(.dsMonoCaption)
                .foregroundStyle(.dsTextTertiary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Space.lg)
            Button("Cancel") { dismiss() }
                .buttonStyle(.ds(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Check Again") { complete() }
                .buttonStyle(.ds(.primary))
                .help("Signed in another way? Native restarts \(request.agent.displayName) to pick it up.")
        }
        .padding(DS.Space.lg)
    }

    private func start() {
        guard run == nil else { return }
        let appearance = TerminalAppearance(colorScheme)
        terminals.setAppearance(appearance, chrome: .designSystem(appearance: appearance, palette: palette))
        run = AgentTerminalSignInRun(request: request, terminals: terminals)
    }

    /// Ends the command and hands over to the app, which restarts the agent and carries on; the
    /// agent's own status shows that progress once the sheet closes.
    private func complete() {
        guard !isFinishing else { return }
        isFinishing = true
        run?.end()
        Task { await finish(request) }
        dismiss()
    }
}
