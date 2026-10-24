import ACP
import SwiftUI

/// A roster, rather than silently opening the first worker when several are on the task.
struct TaskWellSubagentsRoster: View {
    let session: SessionModel
    let open: (SessionID) -> Void

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            if session.state.subagents.isEmpty {
                Text("No subagents on this task")
                    .font(.dsBody).foregroundStyle(.dsTextTertiary)
            }
            ForEach(session.state.subagents) { subagent in
                let child = session.child(subagent.id)
                Button {
                    open(subagent.id)
                } label: {
                    HStack(spacing: DS.TaskWell.gap) {
                        TaskSignal(
                            status: subagent.workState == nil ? child?.taskStatus ?? .idle : status(subagent),
                            placement: .well,
                            attentionSince: child?.taskWellAttentionSince
                        )
                        .frame(width: DS.TaskWell.signal, height: DS.TaskWell.signal)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(subagent.title ?? "Subagent").font(.dsCalloutMedium)
                            Text(subagent.description ?? SubagentStatusLabel.text(for: subagent.workState))
                                .font(.dsBody).foregroundStyle(.dsTextTertiary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: DS.Space.sm)
                        Image(systemName: "chevron.right").foregroundStyle(.dsTextTertiary)
                    }
                    .padding(DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .dsHitTarget(DS.TaskWell.rowHeight)
            }
        }
    }

    private func status(_ subagent: SubagentState) -> TaskStatus {
        switch subagent.workState {
        case .running: .working
        case .requiresAction: .needsPermission
        case .idle(.error, _): .failed
        case .idle(.cancelled, _): .cancelled
        case .idle: .done
        case .unknown, .other, nil: .idle
        }
    }
}

#if DEBUG
#Preview("Well - Worker roster") {
    let app = AppModel.preview()
    return DSPreviewPair {
        if let session = SessionModel.preview(in: app) {
            let _ = SubagentPreviewFixtures.subagents.forEach { subagent in
                session.state.apply(
                    .subagent(
                        SubagentUpdate(
                            sessionId: subagent.id, title: subagent.title.map(Patch.set) ?? .unchanged,
                            description: subagent.description.map(Patch.set) ?? .unchanged,
                            state: subagent.workState.map(Patch.set) ?? .unchanged)))
            }
            TaskWellSubagentsRoster(session: session, open: { _ in })
                .frame(width: DS.TaskWell.panelWidth)
        }
    }
}
#endif
