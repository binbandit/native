import NativeAutomation
import SwiftUI

/// A step's own conversation beside its run, like a subagent's: who's running it, where it stands,
/// its transcript, and a reply box while it's stopped and waiting on the user.
struct WorkflowStepInspector<Transcript: View>: View {
    let step: WorkflowStepRun
    let send: (WorkflowEvent) -> Void
    @ViewBuilder let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            SeparatorLine()
            transcript
                .frame(maxHeight: .infinity)
            if step.status.isStopped, step.task != nil {
                SeparatorLine()
                WorkflowReplyField(agentName: step.assignment.agent?.name ?? "the agent") { send(.reply(step: step.id, text: $0)) }
                    .padding(DS.Space.lg)
            }
        }
        .background(.dsBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            AutomationStatusGlyph(glyph: AutomationGlyph(step: step.status))
                .padding(.top, DS.Space.xxs)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(step.step.title)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Text([step.assignment.agent?.name, step.status.label, step.status.reason].compactMap(\.self).joined(separator: " · "))
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(2)
            }
            .tracking(DS.Tracking.tight)
            Spacer(minLength: DS.Space.md)
            if step.status.isActive {
                Button("Stop Step", systemImage: "stop.fill") { send(.stop(step: step.id)) }
                    .buttonStyle(.ds(.secondary))
                    .help("Stop this step's turn without stopping the workflow")
            }
        }
        .padding(DS.Space.lg)
    }
}
