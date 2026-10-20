import NativeAutomation
import SwiftUI

/// A prompt Native sent to drive a goal, as one quiet line in the transcript instead of a wall of
/// instructions: "Goal set" with the objective, or "Continue · iteration 3". The full prompt is a
/// click away, for anyone who wants to see exactly what the agent was told.
struct GoalPromptRow: View {
    let prompt: GoalPrompt
    /// The text that was sent.
    let text: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Button {
                withAnimation(.dsDisclosure) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.dsAccentText)
                        .frame(width: DS.Size.rowLeading)
                    Text(title)
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextSecondary)
                    Text(prompt.objective)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.dsTextQuaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .tracking(DS.Tracking.tight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide what Native sent" : "Show what Native sent")
            if isExpanded {
                Text(text)
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .textSelection(.enabled)
                    .padding(DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card))
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch prompt {
        case .kickoff: "target"
        case .continuation: "arrow.clockwise"
        }
    }

    private var title: String {
        switch prompt {
        case .kickoff: "Goal set"
        case .continuation(_, let iteration): "Continue · iteration \(iteration)"
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Goal prompt rows") {
    let goal = AutomationPreviewFixtures.activeGoal
    let usage = goal.usage(at: AutomationPreviewFixtures.now)
    let kickoff = GoalPrompt.kickoffText(objective: goal.objective, usage: usage)
    let next = GoalPrompt.continuationText(objective: goal.objective, usage: usage, reminder: false, resumed: false)
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if let prompt = GoalPrompt(parsing: kickoff) {
                GoalPromptRow(prompt: prompt, text: kickoff)
            }
            if let prompt = GoalPrompt(parsing: next) {
                GoalPromptRow(prompt: prompt, text: next)
            }
        }
        .frame(width: 560)
    }
}
#endif
