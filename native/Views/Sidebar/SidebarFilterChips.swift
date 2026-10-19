import SwiftUI
import TaskList

/// The active filters under the Projects header, each removable, with Clear All; the sort shows
/// when it isn't the usual one. Nothing filters silently.
struct SidebarFilterChips: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: TaskFilter

    var body: some View {
        FlowLayout(spacing: DS.Space.xs) {
            ForEach(filter.chips, id: \.self) { chip in
                SidebarFilterChip(title: title(of: chip)) {
                    withAnimation(.dsQuick) { filter.remove(chip) }
                }
            }
            if filter.sort != .recent {
                SidebarFilterChip(title: "Sorted by \(filter.sort.title.lowercased())") {
                    withAnimation(.dsQuick) { filter.sort = .recent }
                }
            }
            Button("Clear All") {
                withAnimation(.dsQuick) { filter = TaskFilter() }
            }
            .buttonStyle(.plain)
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .frame(minHeight: DS.Size.controlXS)
            .dsHitTarget(DS.Size.controlXS)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.bottom, DS.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active Filters")
    }

    private func title(of chip: TaskFilter.Chip) -> String {
        switch chip {
        case .status(let status): status.title
        case .agent(let id): model.agents.first { $0.agent.id.rawValue == id }?.agent.displayName ?? id
        case .uncommittedChanges: "Uncommitted changes"
        case .pullRequest: "Has a PR"
        case .archived: "With archived"
        }
    }
}

/// A compact chip: the filter's name and a remove button.
private struct SidebarFilterChip: View {
    let title: String
    let remove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: remove) {
            HStack(spacing: DS.Space.xxs) {
                Text(title)
                    .font(.dsCaptionMedium)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.dsMicro)
                    .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextTertiary)
            }
            .padding(.horizontal, DS.Space.sm)
            .frame(minHeight: DS.Size.controlXS - DS.Space.xs)
            .background(isHovered ? .dsSelected : .dsHover, in: .capsule)
            .overlay { Capsule().strokeBorder(.dsBorder, lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .dsHitTarget(DS.Size.controlXS)
        .help("Remove the “\(title)” filter")
        .accessibilityLabel("\(title) filter")
        .accessibilityHint("Removes it")
    }
}
