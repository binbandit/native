import ACP
import SwiftUI

/// Every agent's health at the footer's leading edge, where the reference app shows the plan badge: each
/// agent's glyph with a status dot, and its name when there's room. Clicking one shows its details,
/// with a way to retry it or sign in.
struct AgentHealthBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips(showsNames: true)
            chips(showsNames: false)
        }
    }

    private func chips(showsNames: Bool) -> some View {
        HStack(spacing: showsNames ? DS.Space.lg : DS.Space.md) {
            ForEach(model.agents, id: \.agent.id) { runtime in
                AgentHealthChip(runtime: runtime, showsName: showsNames)
            }
        }
        .fixedSize()
    }
}

/// One agent: its glyph with a status dot, and maybe its name.
private struct AgentHealthChip: View {
    let runtime: AgentRuntime
    let showsName: Bool

    @State private var isShowingDetails = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: runtime.agent.symbolName)
                    .font(.dsCaption)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                    .overlay(alignment: .bottomTrailing) {
                        AgentStatusDot(health: AgentHealth(runtime))
                            .offset(x: DS.Space.xxs, y: DS.Space.xxs)
                    }
                if showsName {
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
        .help("\(runtime.agent.displayName): \(AgentHealth(runtime).summary(for: runtime))")
        .accessibilityLabel(runtime.agent.displayName)
        .accessibilityValue(AgentHealth(runtime).summary(for: runtime))
        .accessibilityHint("Shows details")
        .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
            AgentDetailsView(runtime: runtime)
        }
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

/// A 6pt status dot, pulsing while the agent starts or signs in.
private struct AgentStatusDot: View {
    let health: AgentHealth

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if health.isInProgress && !reduceMotion {
            StatusDot(color: health.color)
                .phaseAnimator([1, 0.35]) { dot, opacity in
                    dot.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.6)
                }
        } else {
            StatusDot(color: health.color)
        }
    }
}
