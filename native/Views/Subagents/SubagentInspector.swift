import ACP
import SwiftUI

/// A subagent's own conversation, beside its parent's. Subagents can't be prompted, only watched
/// and, when the agent allows it, stopped.
struct SubagentInspector: View {
    let subagent: SubagentState
    /// The child session, once the agent has sent any of its traffic.
    let child: SessionModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let child {
                TranscriptView(session: child) { _ in }
            } else {
                ContentUnavailableView(
                    "Waiting for the subagent", systemImage: "person.2",
                    description: Text("Its conversation appears here as it works.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .background(.dsBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(subagent.title ?? "Subagent")
                    .font(.headline)
                if let description = subagent.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                SubagentStatusLabel(state: subagent.workState)
            }
            Spacer(minLength: 8)
            if subagent.canCancel, subagent.workState?.isWorking == true, let child {
                Button("Stop", systemImage: "stop.fill") {
                    Task { await child.cancel() }
                }
                .dsGlassButtonStyle()
                .help("Stop this subagent without stopping the main session")
            }
        }
        .padding(16)
    }
}
