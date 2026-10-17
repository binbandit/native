import ACP
import SwiftUI

/// An agent's details, from its footer chip: what it is and how it's doing, its usage limit, why it
/// stopped or how to install it, the ways to sign in, and Retry or Restart.
struct AgentDetailsView: View {
    @Environment(AppModel.self) private var model
    let runtime: AgentRuntime
    let limit: LimitStatus?

    private var health: AgentHealth {
        AgentHealth(runtime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                AgentIcon(agent: runtime.agent, size: DS.Size.controlXS)
                    .foregroundStyle(.dsTextSecondary)
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

            if let limit {
                TimelineView(.everyMinute) { context in
                    Text(limit.line(now: context.date))
                        .font(.dsBody)
                        .foregroundStyle(limit.level == .reached ? .dsDanger : .dsWarning)
                        .fixedSize(horizontal: false, vertical: true)
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

    /// "Ready · claude-code-acp 0.9", or the status alone while it isn't ready.
    private var detailLine: String {
        guard health == .ready, let info = runtime.info else { return health.summary(for: runtime) }
        return ["Ready", info.name, info.version].compactMap(\.self).joined(separator: " · ")
    }
}
