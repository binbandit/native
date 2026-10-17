import ACP
import SwiftUI

/// The agent's current plan (its todo list), shown above the composer.
struct PlanView: View {
    let entries: [PlanEntry]

    @State private var isExpanded = true

    private var completedCount: Int {
        entries.count(where: { $0.status == .completed })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                HeightCappedScrollView(maxHeight: 220) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entries.indices, id: \.self) { index in
                            PlanEntryRow(entry: entries[index])
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .transcriptCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("Plan")
                .fontWeight(.medium)
            Text(verbatim: "\(completedCount)/\(entries.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            // Collapsed, the header still says what the agent is working on.
            if !isExpanded, let current = entries.first(where: { $0.status == .inProgress }) {
                Text(current.content)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            DisclosureChevron(isExpanded: isExpanded)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(.rect)
    }
}

private struct PlanEntryRow: View {
    let entry: PlanEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            glyph
                .frame(width: 14)
            Text(entry.content)
                .strikethrough(entry.status == .completed, color: .secondary)
                .foregroundStyle(entry.status == .completed ? .secondary : .primary)
                .fontWeight(entry.status == .inProgress ? .medium : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    private var glyph: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(entry.status == .inProgress ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .contentTransition(.symbolEffect(.replace))
            .animation(.smooth, value: entry.status)
    }

    private var symbolName: String {
        switch entry.status {
        case .pending: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        }
    }
}

#if DEBUG
#Preview("Plan") {
    PlanView(entries: TranscriptFixtures.plan)
        .padding(20)
        .frame(width: 520)
}
#endif
