import SwiftUI

/// A recent task on the home page, laid out like a row of Conductor's workspace overview
/// (`OverviewRow`): a 16pt leading glyph, the title, then fixed trailing columns so ages line up
/// down the list. The glyph is the agent's, since the list mixes agents.
struct HomeTaskRow<ID: Hashable>: View {
    let task: HomeTask<ID>
    /// The trailing label: the project, or the agent when every task shares a project. A narrow
    /// column leaves it out so the title keeps the room.
    let detail: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md + DS.Space.xxs) {
                Image(systemName: task.agentSymbolName)
                    .font(.system(size: DS.Size.navIcon))
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                Text(task.title)
                    .font(.dsCalloutBook)
                    .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: DS.Space.md)
                if let detail {
                    Text(detail)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: HomeLayout.taskDetailWidth, alignment: .trailing)
                }
                age
                    .frame(width: HomeLayout.ageColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.md + DS.Space.xxs)
            .frame(minHeight: HomeLayout.minTapHeight)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityLabel(task.title)
        .accessibilityValue(accessibilityValue)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
    }

    @ViewBuilder private var age: some View {
        if let date = task.date {
            // Re-rendered each minute so "now" doesn't linger while the page stays open.
            TimelineView(.everyMinute) { context in
                Text(DSFormat.compactAge(date, now: context.date))
                    .font(.dsBody)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
            }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private var accessibilityValue: String {
        let parts =
            [task.agentName, task.projectName, task.date?.formatted(.relative(presentation: .named))] as [String?]
        return parts.compactMap(\.self).joined(separator: ", ")
    }
}
