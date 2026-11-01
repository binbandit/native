import ACP
import SwiftUI

/// The agents before a change of agent, above where the new one took over: each one's messages and
/// tool calls under its name, read-only, drawn the way the transcript draws its own. So a task reads
/// as one conversation whichever agent it's on now.
struct TaskHistoryContextView: View {
    let context: TaskHistoryContext

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            if context.omitsEarlier {
                Text("Earlier messages are in the earlier conversations.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(context.runs) { run in
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    heading(run)
                    ForEach(run.rows) { row($0) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("From \(run.agentName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, DS.Space.lg)
    }

    private func heading(_ run: TaskHistoryContext.Run) -> some View {
        HStack(spacing: DS.Space.sm) {
            if let agent = run.agent {
                AgentIcon(agent: agent)
            }
            Text(run.agentName)
        }
        .font(.dsCaption.weight(.medium))
        .foregroundStyle(.dsTextSecondary)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func row(_ row: TranscriptRow) -> some View {
        switch row {
        case .item(.message(let message)):
            MessageView(message: message)
        case .item(.toolCall(let call)):
            // Read-only: nothing here can be approved or answered.
            ToolCallView(call: call) { _ in }
        case .toolGroup(let group):
            ToolGroupView(group: group, isLive: false)
        case .item(.notice), .item(.subagent), .item(.sessionMessage):
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Task history - Earlier agents before a change") {
    DSPreviewPair {
        VStack(spacing: 0) {
            TaskHistoryContextView(context: TaskHistoryPreviewFixtures.twoAgents)
            ChangeAgentDivider(agentName: "Claude Code")
        }
        .frame(width: 560)
        .padding()
    }
}

#Preview("Task history - A long conversation's newest messages") {
    DSPreviewPair {
        VStack(spacing: 0) {
            TaskHistoryContextView(context: TaskHistoryPreviewFixtures.omitsEarlier)
            ChangeAgentDivider(agentName: "Claude Code")
        }
        .frame(width: 560)
        .padding()
    }
}
#endif
