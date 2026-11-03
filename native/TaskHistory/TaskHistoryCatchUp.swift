import ACP
import SwiftUI

/// What other agents did while a returning conversation was away, as one quiet row above the
/// context marker where it came back: "Fake Agent worked while this agent was away". It opens to
/// their messages and tool calls on demand, and starts closed every time the transcript appears.
struct TaskHistoryCatchUp: View {
    let context: TaskHistoryContext
    @State private var isExpanded: Bool

    init(context: TaskHistoryContext, isExpanded: Bool = false) {
        self.context = context
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Button {
                withAnimation(.reveal) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Text(summary)
                        .lineLimit(1)
                    DisclosureChevron(isExpanded: isExpanded)
                }
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .dsHitTarget(DS.Size.controlSM)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hides what they did" : "Shows what they did")
            if isExpanded {
                TaskHistoryContextView(context: context)
                    .transition(RevealTransition())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, isExpanded ? 0 : DS.Space.lg)
    }

    /// The agents by name, once each, in the order they worked.
    private var summary: String {
        var names: [String] = []
        for run in context.runs where !names.contains(run.agentName) { names.append(run.agentName) }
        let who = names.count == 1 ? names[0] : "\(names.count) agents"
        return "\(who) worked while this agent was away"
    }
}

#if DEBUG
#Preview("Task history - Catch-up, collapsed and expanded") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(spacing: 0) {
                TaskHistoryCatchUp(context: TaskHistoryPreviewFixtures.omitsEarlier)
                PromptPreambleMarker(marker: .init(id: "task-history:preview", label: "Earlier context"))
            }
            VStack(spacing: 0) {
                TaskHistoryCatchUp(context: TaskHistoryPreviewFixtures.twoAgents, isExpanded: true)
                PromptPreambleMarker(marker: .init(id: "task-history:preview", label: "Earlier context"))
            }
        }
        .frame(width: 560)
        .padding()
    }
}
#endif
