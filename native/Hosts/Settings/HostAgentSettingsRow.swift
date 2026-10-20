import ACP
import SwiftUI

/// One agent on a host, under the host's row: its icon and name, how it's doing there, and on the
/// trailing edge either Sign In (an action) or its state (a value). An agent the host doesn't have
/// says how to install it there.
struct HostAgentSettingsRow: View {
    let agent: HostAgentDisplay
    let hostName: String
    let isThisMac: Bool
    /// Signs in with `method`, or with nil opens the sheet that explains signing in on a host.
    let signIn: (HostSignInMethod?) -> Void
    /// Looks again; returns why that failed, if it did.
    let checkAgain: () async -> String?

    @State private var isChecking = false
    @State private var checkFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.md) {
                AgentIcon(agent: agent.agent, size: DS.Size.rowLeading)
                Text(agent.agent.displayName)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                statusLabel
                Spacer(minLength: DS.Space.xl)
                trailing
            }
            .frame(minHeight: SettingsMetrics.controlHeight)
            if case .notInstalled = agent.status, let install = agent.installCommand {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(isThisMac ? "Install it in Terminal:" : "Install it on \(hostName), in a terminal there:")
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextSecondary)
                    AgentSetupCommand(command: install)
                }
                .padding(.leading, DS.Size.rowLeading + DS.Space.md)
            } else if case .failed(let message) = agent.status {
                Text(message)
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.leading, DS.Size.rowLeading + DS.Space.md)
            }
            if let checkFailure {
                Label(checkFailure, systemImage: "exclamationmark.triangle")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, DS.Size.rowLeading + DS.Space.md)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Whether it wants a sign-in, else whom it's signed in as, when it says.
    @ViewBuilder private var statusLabel: some View {
        if agent.isSigningIn {
            SettingsBadge("Signing in…")
        } else if agent.wantsSignIn {
            Badge("Needs sign-in", tone: .attention, style: .soft)
        } else if let label = agent.signInLabel {
            Text(agent.isSignedIn == true ? "Signed in as \(label)" : label)
                .settingsText(.caption)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder private var trailing: some View {
        if agent.isSigningIn {
            DotGridLoader(pattern: .waiting)
                .frame(width: HostsMetrics.loader, height: HostsMetrics.loader)
                .accessibilityLabel("Signing in")
        } else if agent.wantsSignIn, isThisMac, let method = agent.methods.first {
            // This Mac signs in the way Settings ▸ Agents does: each method the agent offers.
            if agent.methods.count == 1 {
                Button("Sign In…") { signIn(method) }
                    .buttonStyle(.settings)
            } else {
                Menu("Sign In") {
                    ForEach(agent.methods) { method in
                        Button(method.method.name) { signIn(method) }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.settings)
                .fixedSize()
            }
        } else if agent.wantsSignIn, !isThisMac, agent.canSignIn {
            Button("Sign In…") { signIn(nil) }
                .buttonStyle(.settings)
                .accessibilityLabel("Sign in to \(agent.agent.displayName) on \(hostName)")
        } else if agent.status.canRetry {
            Button(isChecking ? "Checking…" : "Check Again") {
                Task {
                    isChecking = true
                    checkFailure = await checkAgain()
                    isChecking = false
                }
            }
            .buttonStyle(.settings)
            .disabled(isChecking)
            .help("Installed it or fixed what stopped it? Native looks again.")
        } else {
            SettingsValue(agent.status.label)
        }
    }
}
