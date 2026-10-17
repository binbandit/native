import ACP
import SwiftUI

/// An agent's details, from its footer chip: what it is and how it's doing, why it stopped or how
/// to install it, the ways to sign in, and Retry or Restart.
struct AgentDetailsView: View {
    @Environment(AppModel.self) private var model
    let runtime: AgentRuntime

    private var health: AgentHealth {
        AgentHealth(runtime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: runtime.agent.symbolName)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                    .background(.dsSelected, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(runtime.agent.displayName)
                        .font(.dsHeadline)
                        .foregroundStyle(.dsTextPrimary)
                    HStack(spacing: DS.Space.xs) {
                        StatusDot(color: health.color)
                        Text(detailLine)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
            }

            if let guidance = runtime.status.guidance {
                ScrollView {
                    Text(guidance)
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.md)
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            }

            if health == .needsSignIn || health == .signingIn {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Sign in to start sessions with \(runtime.agent.displayName).")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                    ForEach(runtime.authMethods, id: \.id) { method in
                        Button(method.name) {
                            Task { await model.signIn(to: runtime.agent.id, with: method) }
                        }
                        .buttonStyle(.ds(.secondary))
                        .disabled(runtime.isSigningIn)
                        .help(method.description ?? method.name)
                    }
                }
            }

            HStack {
                Spacer()
                Button(runtime.status.canRetry ? "Retry" : "Restart") {
                    Task { await model.restart(runtime.agent.id) }
                }
                .buttonStyle(.ds(runtime.status.canRetry ? .primary : .secondary))
                .disabled(health == .starting)
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 300)
    }

    private var detailLine: String {
        let version = runtime.info.map { [$0.displayName, $0.version].compactMap(\.self).joined(separator: " ") }
        return [health.summary(for: runtime), health == .ready ? nil : version].compactMap(\.self).joined(separator: " · ")
    }
}
