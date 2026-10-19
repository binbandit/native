import SwiftUI

/// One task in the Needs You strip: its status glyph, title and question, and where clicking goes.
struct HomeWaitingTaskRow<ID: Hashable>: View {
    let task: HomeWaitingTask<ID>
    /// Whether there's room for the agent's name at the trailing edge.
    let showsAgent: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md + DS.Space.xxs) {
                StatusIndicator(status: task.status)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + DS.Space.xs }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    DSInlineCodeText(task.title)
                        .font(.dsCalloutMedium)
                        .foregroundStyle(.dsTextPrimary)
                    Text(task.request)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: DS.Space.md)
                if showsAgent {
                    Text(task.agentName)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "arrow.right")
                    .font(.dsCaption)
                    .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextTertiary)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.md)
            .frame(minHeight: DS.Size.minimumHitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
        .accessibilityLabel(task.title)
        .accessibilityValue("\(task.status.label): \(task.request), \(task.agentName)")
        .accessibilityHint("Opens the task")
        .help("Open \(task.title)")
    }
}
