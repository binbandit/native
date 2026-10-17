import ACP
import SwiftUI

/// What can be done to a running agent from its Settings row: sign in when it asks to, or restart
/// it. Signing in to an agent that only signs in from a terminal opens the terminal sign-in sheet.
struct AgentRowActions: View {
    let runtime: AgentRuntime

    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    private var canSignIn: Bool {
        runtime.isReady && runtime.needsSignIn && !runtime.authMethods.isEmpty
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Menu {
            if canSignIn {
                if let method = runtime.authMethods.first, runtime.authMethods.count == 1 {
                    Button("Sign In…") { signIn(with: method) }
                } else {
                    Menu("Sign In") {
                        ForEach(runtime.authMethods, id: \.id) { method in
                            Button(method.name) { signIn(with: method) }
                        }
                    }
                }
                Divider()
            }
            Button("Restart \(runtime.agent.displayName)") {
                Task { await model.restart(runtime.agent.id) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: SettingsMetrics.navGlyph, weight: .regular))
                .foregroundStyle(isHovered ? Color.dsTextPrimary : Color.dsTextSecondary)
                .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                .background(isHovered ? Color.dsHover : .clear, in: shape)
                .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .trackHover($isHovered)
        .help("\(runtime.agent.displayName) actions")
        .accessibilityLabel("\(runtime.agent.displayName) actions")
    }

    private func signIn(with method: AuthMethod) {
        Task { await model.signIn(to: runtime.agent.id, with: method) }
    }
}
