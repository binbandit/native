import SwiftUI

/// The tasks that are working or waiting on the user, those waiting first. Choosing one opens it.
struct TasksPanel: View {
    let source: any StatusBarSource

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let tasks = source.statusBarTasks
        PopoverPanel(title: "Tasks", systemImage: "list.bullet") {
            if !tasks.isEmpty {
                Text("\(tasks.count) active")
            }
        } content: {
            if tasks.isEmpty {
                EmptyStateView(
                    "No tasks running",
                    systemImage: "checkmark.circle",
                    message: "Tasks show here while an agent works on them or waits for you."
                )
                .frame(height: StatusBarMetrics.panelListHeight / 2)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(tasks) { task in
                            TaskActivityRow(task: task) {
                                source.showTask(task.id)
                                dismiss()
                            }
                        }
                    }
                    .padding(DS.Space.xs)
                }
                .frame(maxHeight: StatusBarMetrics.panelListHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A task: its status glyph, title, agent and project, and what it's doing in words.
private struct TaskActivityRow: View {
    let task: TaskActivity
    let action: () -> Void

    @State private var isHovered = false

    private var detail: String {
        [task.agentName, task.projectName].compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                StatusIndicator(status: task.status)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    DSInlineCodeText(task.title)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextPrimary)
                    Text(detail)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
                .lineLimit(1)
                Spacer(minLength: DS.Space.md)
                Text(task.status.label)
                    .font(.dsCaption)
                    .foregroundStyle(task.needsAttention ? .dsAccentText : .dsTextSecondary)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(isHovered ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help("Open \(task.title)")
        .accessibilityLabel(task.title)
        .accessibilityValue("\(task.status.label), \(detail)")
    }
}
