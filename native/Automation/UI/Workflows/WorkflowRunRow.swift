import SwiftUI

/// A workflow run in the sidebar: a task row like any other, with the workflow's glyph leading and
/// its progress as the subtitle, flagged when a step needs the user.
struct WorkflowRunRow: View {
    let run: WorkflowRun
    var isSelected = false
    let action: () -> Void

    var body: some View {
        TaskRow(
            title: run.title,
            status: status,
            isSelected: isSelected,
            subtitle: "\(run.definition.name) · \(run.finishedCount)/\(run.steps.count)",
            date: run.endedAt ?? run.createdAt,
            badge: badge,
            // No workflow glyph: the row is narrow, and the subtitle already names the workflow.
            leading: EmptyView(),
            accessory: EmptyView(),
            action: action
        )
    }

    private var status: TaskStatus {
        AutomationGlyph(run: run.phase).taskStatus
    }

    private var badge: TaskBadge? {
        switch run.phase {
        case .awaitingApproval: .attention("Approve")
        case .blocked: .attention("Reply")
        case .halted: .attention(run.statusLabel)
        default: nil
        }
    }
}
