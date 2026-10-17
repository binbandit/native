import SwiftUI

/// The recent tasks under the cards, headed like a group in Conductor's workspace overview: the
/// title in medium weight with a fainter count, and rows that fill on hover.
struct HomeRecentTasks<ID: Hashable>: View {
    let tasks: [HomeTask<ID>]
    /// How many tasks there are in all, when the list shows only the latest.
    let totalCount: Int
    let onSelect: (ID) -> Void

    @State private var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text("Recent tasks")
                    .foregroundStyle(.dsTextSecondary)
                Text("\(totalCount)")
                    .foregroundStyle(.dsTextTertiary)
                    .monospacedDigit()
            }
            .font(.dsCalloutMedium)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(tasks) { task in
                HomeTaskRow(task: task, detail: detail(for: task)) {
                    onSelect(task.id)
                }
            }
        }
        .frame(maxWidth: HomeLayout.columnWidth)
        .onGeometryChange(for: Bool.self) {
            $0.size.width < HomeLayout.compactWidth
        } action: {
            isCompact = $0
        }
    }

    /// The row's trailing label: its project when the tasks span projects, else its agent (the glyph
    /// shows the agent either way), and nothing in a narrow column.
    private func detail(for task: HomeTask<ID>) -> String? {
        guard !isCompact else { return nil }
        let spansProjects = Set(tasks.compactMap(\.projectName)).count > 1
        return spansProjects ? task.projectName ?? task.agentName : task.agentName
    }
}
