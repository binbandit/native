import SwiftUI

/// The recent tasks under the cards, headed like a group in Conductor's workspace overview: the
/// title in medium weight with a fainter count, and rows that fill on hover.
struct HomeRecentTasks<ID: Hashable>: View {
    let tasks: [HomeTask<ID>]
    /// How many tasks there are in all, when the list shows only the latest.
    let totalCount: Int
    let onSelect: (ID) -> Void

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
                HomeTaskRow(task: task, detail: spansProjects ? task.projectName ?? task.agentName : task.agentName) {
                    onSelect(task.id)
                }
            }
        }
        .frame(maxWidth: HomeLayout.columnWidth)
    }

    /// Whether to label rows with their project. When every task is in one project the label
    /// tells them apart by agent instead; the glyph already shows the agent either way.
    private var spansProjects: Bool {
        Set(tasks.compactMap(\.projectName)).count > 1
    }
}
