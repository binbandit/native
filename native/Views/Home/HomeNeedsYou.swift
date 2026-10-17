import SwiftUI

/// The tasks waiting on the user, above the agent cards: each with what it's asking, and a click
/// away. Outlined in the attention color so it reads as the page's one urgent thing; the page shows
/// nothing here when no task is waiting.
struct HomeNeedsYou<ID: Hashable>: View {
    let tasks: [HomeWaitingTask<ID>]
    let onSelect: (ID) -> Void

    @State private var isCompact = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text("Needs you")
                    .foregroundStyle(.dsTextPrimary)
                Text("\(tasks.count)")
                    .foregroundStyle(.dsTextTertiary)
                    .monospacedDigit()
            }
            .font(.dsCalloutMedium)
            .padding(.horizontal, DS.Space.md)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, DS.Space.xxs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(tasks) { task in
                HomeWaitingTaskRow(task: task, showsAgent: !isCompact) {
                    onSelect(task.id)
                }
            }
        }
        .padding(DS.Space.sm)
        .background(.dsSurface, in: shape)
        .overlay { shape.strokeBorder(.dsAttention.opacity(HomeLayout.attentionOutlineOpacity), lineWidth: 1) }
        .onGeometryChange(for: Bool.self) {
            $0.size.width < HomeLayout.compactWidth
        } action: {
            isCompact = $0
        }
    }
}
