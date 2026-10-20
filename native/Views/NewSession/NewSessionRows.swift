import SwiftUI

/// A task to go back to: its status where it has one worth seeing, title, agent and age. The whole
/// row opens it.
struct NewSessionTaskRow: View {
    let task: NewSessionContext.RecentTask
    var showsDetail = true

    var body: some View {
        NewSessionListRow(action: task.open) {
            Group {
                if task.status == .idle {
                    Image(systemName: "text.bubble")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                } else {
                    StatusIndicator(status: task.status, size: DS.Size.statusGlyph)
                }
            }
            .frame(width: DS.Size.rowLeading)
            Text(task.title)
                .font(.dsCallout)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.md)
            if showsDetail {
                Text(task.status.needsAttention ? task.status.label : task.agentName)
                    .font(.dsBody)
                    .foregroundStyle(task.status.needsAttention ? .dsAttention : .dsTextTertiary)
                    .lineLimit(1)
            }
            if let date = task.date {
                CompactAgeText(date: date)
                    .frame(width: NewSessionMetrics.ageColumn, alignment: .trailing)
            }
        }
        .accessibilityLabel(task.title)
        .accessibilityValue(
            [task.status == .idle ? nil : task.status.label, task.agentName].compactMap(\.self).formatted()
        )
        .accessibilityHint("Opens the task")
    }
}

/// A pull request to take up: number, title, branch, and Open as Task, which the whole row does.
/// The trailing label stays visible, so touch sees what a tap does.
struct NewSessionPullRequestRow: View {
    let pullRequest: NewSessionContext.PullRequest
    var showsDetail = true

    var body: some View {
        NewSessionListRow(action: pullRequest.openAsTask ?? {}) {
            Text("#\(pullRequest.number)")
                .font(.dsMonoCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: NewSessionMetrics.numberColumn, alignment: .leading)
            Text(pullRequest.title)
                .font(.dsCallout)
                .foregroundStyle(pullRequest.isDraft ? .dsTextSecondary : .dsTextPrimary)
                .lineLimit(1)
            if pullRequest.isReviewRequested {
                Badge("Review", tone: .attention)
            } else if pullRequest.isDraft {
                Badge("Draft")
            }
            Spacer(minLength: DS.Space.md)
            if showsDetail, let branch = pullRequest.branch {
                Text(branch)
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: NewSessionMetrics.detailColumn, alignment: .trailing)
            }
            if pullRequest.openAsTask != nil {
                Label("Open as Task", systemImage: "arrow.down.to.line.compact")
                    .labelStyle(.iconOnly)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: NewSessionMetrics.ageColumn, alignment: .trailing)
                    .help("Open as Task: check out the branch in a worktree, with a task there")
            }
        }
        .disabled(pullRequest.openAsTask == nil)
        .accessibilityLabel("#\(pullRequest.number) \(pullRequest.title)")
        .accessibilityHint(pullRequest.openAsTask == nil ? "" : "Opens it as a task")
    }
}

/// A list row: content in a line, a hover wash, the pressed wash, and a touch-sized target.
struct NewSessionListRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                content
            }
            .padding(.horizontal, DS.Space.sm)
            .frame(minHeight: max(NewSessionMetrics.listRow, DS.Size.minimumHitTarget))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
        .accessibilityElement(children: .combine)
    }
}
