import ACP
import SwiftUI

/// Every agent's health at the footer's leading edge, where Conductor shows the plan badge: each
/// agent's glyph with a status dot, with its name, or its usage limit when it's near or at one, as
/// room allows. Clicking one shows its details, with a way to retry it or sign in.
struct AgentHealthBar: View {
    @Environment(AppModel.self) private var model
    /// Where each agent stands against its usage limits; Usage supplies it.
    let limitStatus: (AgentDefinition.ID) -> LimitStatus?

    var body: some View {
        // Most detail first; a limit outranks a name, since it changes what the user can do.
        ViewThatFits(in: .horizontal) {
            chips(.full)
            chips(.limitsOnly)
            chips(.glyphs)
        }
    }

    private func chips(_ detail: AgentHealthChip.Detail) -> some View {
        HStack(spacing: detail == .glyphs ? DS.Space.md : DS.Space.lg) {
            ForEach(model.agents, id: \.agent.id) { runtime in
                AgentHealthChip(runtime: runtime, limit: limitStatus(runtime.agent.id), detail: detail)
            }
        }
        .fixedSize()
    }
}

/// One agent: its glyph with a status dot, and its name or limit as `detail` allows.
private struct AgentHealthChip: View {
    enum Detail {
        /// Names, and limits in their place.
        case full
        /// Limits only.
        case limitsOnly
        /// Glyphs only; a limit tints the dot.
        case glyphs
    }

    let runtime: AgentRuntime
    let limit: LimitStatus?
    let detail: Detail

    @State private var isShowingDetails = false
    @State private var isHovered = false

    private var health: AgentHealth {
        AgentHealth(runtime)
    }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Button {
                isShowingDetails.toggle()
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: runtime.agent.symbolName)
                        .font(.dsCaption)
                        .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                        .overlay(alignment: .bottomTrailing) {
                            AgentStatusDot(health: health, limit: detail == .glyphs ? limit : nil)
                                .offset(x: DS.Space.xxs, y: DS.Space.xxs)
                        }
                    if detail == .full, limit == nil {
                        Text(runtime.agent.displayName)
                            .font(.dsBody)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(isHovered || isShowingDetails ? .dsTextPrimary : .dsTextSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .trackHover($isHovered)
            .help(summary(now: .now))
            .accessibilityLabel(runtime.agent.displayName)
            .accessibilityValue(summary(now: .now))
            .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
                AgentDetailsView(runtime: runtime, limit: limit)
            }

            if let limit, detail != .glyphs {
                LimitChip(status: limit) { isShowingDetails = true }
            }
        }
    }

    /// The status, and the limit in the shared wording when there is one.
    private func summary(now: Date) -> String {
        let status = "\(runtime.agent.displayName): \(health.summary(for: runtime))"
        return [status, limit?.line(now: now)].compactMap(\.self).joined(separator: "\n")
    }
}

/// What the footer shows for an agent: its runtime status, with signing in folded in.
enum AgentHealth: Equatable {
    case starting, ready, needsSignIn, signingIn, notInstalled, failed

    init(_ runtime: AgentRuntime) {
        if runtime.isReady {
            self = runtime.isSigningIn ? .signingIn : runtime.needsSignIn ? .needsSignIn : .ready
            return
        }
        switch runtime.status.severity {
        case .progress, .ok: self = .starting
        case .attention: self = .notInstalled
        case .problem: self = .failed
        }
    }

    /// The dot's color. A missing agent is grey: it isn't broken, it was never installed.
    var color: Color {
        switch self {
        case .starting, .signingIn: .dsTextTertiary
        case .ready: .dsSuccess
        case .needsSignIn: .dsWarning
        case .notInstalled: .dsTextQuaternary
        case .failed: .dsDanger
        }
    }

    var isInProgress: Bool {
        self == .starting || self == .signingIn
    }

    /// A one-line status for tooltips and VoiceOver.
    func summary(for runtime: AgentRuntime) -> String {
        switch self {
        case .ready: ["Ready", runtime.info?.version].compactMap(\.self).joined(separator: " · ")
        case .needsSignIn: "Signed out"
        case .signingIn: "Signing in…"
        case .starting, .notInstalled, .failed: runtime.status.label
        }
    }
}

/// A 6pt status dot, pulsing while the agent starts or signs in. With room for nothing else, a limit
/// takes over its color: warning near the limit, danger at it.
private struct AgentStatusDot: View {
    let health: AgentHealth
    var limit: LimitStatus?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch limit?.level {
        case .reached: .dsDanger
        case .warning: .dsWarning
        case nil: health.color
        }
    }

    var body: some View {
        if health.isInProgress && !reduceMotion {
            StatusDot(color: color)
                .phaseAnimator([1, 0.35]) { dot, opacity in
                    dot.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.6)
                }
        } else {
            StatusDot(color: color)
        }
    }
}
