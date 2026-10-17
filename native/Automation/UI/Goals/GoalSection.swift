import NativeAutomation
import SwiftUI

/// A task's goal as the composer's top section, after Factory's mission bar: the status in an
/// uppercase mono label, the objective, its spend against the budget, what the loop is doing or why
/// it stopped, and the one action that moves it on.
struct GoalSection: View {
    struct Actions {
        var pause: () -> Void = {}
        var resume: () -> Void = {}
        var extendAndResume: () -> Void = {}
        var clear: () -> Void = {}
        var edit: () -> Void = {}
    }

    let goal: Goal
    /// Whether the agent is in a turn right now.
    let isWorking: Bool
    let agentName: String
    var actions = Actions()

    var body: some View {
        // Elapsed time moves while the goal is active; a minute is the finest the bar shows.
        TimelineView(.periodic(from: .now, by: goal.status == .active ? 15 : 3600)) { timeline in
            content(GoalPresentation(goal: goal, isWorking: isWorking, agentName: agentName, at: timeline.date))
        }
    }

    private func content(_ presentation: GoalPresentation) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .center, spacing: DS.Space.md) {
                AutomationStatusGlyph(glyph: presentation.glyph)
                Badge(presentation.label, tone: tone(presentation), style: .mono)
                Text(goal.objective)
                    .font(.dsBodyMedium)
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(goal.objective)
                Spacer(minLength: DS.Space.md)
                Text(presentation.usage)
                    .font(.dsMonoCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .help(presentation.usageHelp)
                trailingActions(presentation)
            }
            Text(presentation.detail)
                .font(.dsCaption)
                .tracking(DS.Tracking.tight)
                .foregroundStyle(goal.status == .blocked ? .dsAttention : .dsTextSecondary)
                .lineLimit(2)
                .padding(.leading, DS.Size.rowLeading + DS.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let fraction = presentation.fraction, goal.status != .complete {
                BudgetBar(fraction: fraction)
                    .padding(.leading, DS.Size.rowLeading + DS.Space.md)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md + DS.Space.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Goal, \(presentation.label): \(goal.objective)")
    }

    @ViewBuilder
    private func trailingActions(_ presentation: GoalPresentation) -> some View {
        HStack(spacing: DS.Space.xxs) {
            switch presentation.primaryAction {
            case .pause:
                IconButton("Pause Goal", systemImage: "pause.fill", action: actions.pause)
            case .resume:
                Button("Resume", systemImage: "play.fill", action: actions.resume)
                    .buttonStyle(.ds(.secondary))
            case .extendAndResume:
                Button("Extend Budget", systemImage: "arrow.clockwise", action: actions.extendAndResume)
                    .buttonStyle(.ds(.secondary))
                    .help("Grant the same budget again and keep going")
            case .clear:
                Button("Clear", action: actions.clear)
                    .buttonStyle(.ds(.ghost))
            case nil:
                EmptyView()
            }
            Menu {
                // ⌥⌘G belongs to the Session menu's item (docs/keyboard.md), not this copy of it.
                Button("Edit Goal…", action: actions.edit)
                if goal.status == .active {
                    Button("Pause Goal", action: actions.pause)
                } else if goal.status.isResumable {
                    Button("Resume Goal", action: actions.resume)
                }
                Divider()
                Button("Clear Goal", role: .destructive, action: actions.clear)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Goal options")
            .accessibilityLabel("Goal options")
        }
    }

    private func tone(_ presentation: GoalPresentation) -> Badge.Tone {
        switch goal.status {
        case .active: .accent
        case .blocked: .attention
        case .limited: .warning
        case .complete: .success
        case .paused: .neutral
        }
    }
}

/// How much of the tightest budget is spent: accent, then warning past 80%, then error at 100%,
/// like the usage meters.
private struct BudgetBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.dsSelected)
                Rectangle()
                    .fill(fraction >= 1 ? Color.dsDangerMeterFill : fraction >= 0.8 ? .dsWarningFill : .dsAccent)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: DS.Space.xxs)
        .clipShape(.rect(cornerRadius: DS.Radius.small))
        .animation(.dsQuick, value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Budget used")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}
