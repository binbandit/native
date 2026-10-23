import SwiftUI

struct QuickEntryStartedToast: View {
    let task: StartingTask
    let project: String
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Text(message)
                .font(.dsCallout)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(2)
            Button(task.failure == nil ? "Open" : "Show Details", action: open)
                .buttonStyle(.ds(.ghost))
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.ds(.ghost))
                .accessibilityLabel("Dismiss task confirmation")
        }
        .padding(DS.Space.sm)
        .padding(.leading, DS.Space.md)
        .background(.dsOverlay, in: .rect(cornerRadius: DS.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsBorder) }
        .dsShadow(.modal)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var message: String {
        if let failure = task.failure { return failure.title }
        return task.openedSession == nil
            ? "\(task.agent.displayName) is starting in \(project)"
            : "Started \(task.agent.displayName) in \(project)"
    }
}

#if DEBUG
#Preview("Quick Entry - Starting, started and failed") {
    DSPreviewPair {
        let model = AppModel.preview()
        if let project = model.previewProject(), let agent = model.agents.first?.agent {
            let task = StartingTask(
                project: project.id, agent: agent, isAgentPicked: true, workspaceLabel: "Creating a worktree")
            VStack(spacing: DS.Space.lg) {
                QuickEntryStartedToast(task: task, project: "native", open: {}, dismiss: {})
                let completed = StartingTask(
                    project: project.id, agent: agent, isAgentPicked: true, workspaceLabel: "Creating a worktree")
                let _ = completed.openedSession = completed.id
                QuickEntryStartedToast(task: completed, project: "native", open: {}, dismiss: {})
                let failed = StartingTask(
                    project: project.id, agent: agent, isAgentPicked: true, workspaceLabel: "Creating a worktree")
                let _ =
                    failed.failure = .init(
                        title: "Couldn't create the task's workspace", message: "The folder is unavailable.")
                QuickEntryStartedToast(task: failed, project: "native", open: {}, dismiss: {})
            }
            .padding(DS.Space.xl)
        }
    }
}
#endif
