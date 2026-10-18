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
                withAnimation(.dsDisclosure) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                HeightCappedScrollView(maxHeight: TranscriptMetrics.planMaxHeight) {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        ForEach(entries.indices, id: \.self) { index in
                            PlanEntryRow(entry: entries[index])
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.vertical, DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .transcriptCard()
    }

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "checklist")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.dsTextSecondary)
            Text("Plan")
                .font(.dsBodyMedium)
            Text(verbatim: "\(completedCount)/\(entries.count)")
                .monospacedDigit()
                .foregroundStyle(.dsTextSecondary)
            // Collapsed, the header still says what the agent is working on.
            if !isExpanded, let current = entries.first(where: { $0.status == .inProgress }) {
                Text(current.content)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: DS.Space.md)
            DisclosureChevron(isExpanded: isExpanded)
        }
        .font(.dsBody)
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.md)
        .contentShape(.rect)
    }
}

private struct PlanEntryRow: View {
    let entry: PlanEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            glyph
                .frame(width: DS.Size.statusGlyph)
            Text(entry.content)
                .strikethrough(entry.status == .completed, color: .dsTextSecondary)
                .foregroundStyle(entry.status == .completed ? Color.dsTextSecondary : .dsTextPrimary)
                .font(entry.status == .inProgress ? .dsBodyMedium : .dsBody)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.dsBody)
    }

    @ViewBuilder private var glyph: some View {
        if entry.status == .inProgress {
            // The step being worked on is live, in the one loader family.
            DotGridLoader(pattern: .waiting)
                .foregroundStyle(.dsAccent)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                .accessibilityLabel("In progress")
        } else {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.dsTextSecondary)
                .contentTransition(.symbolEffect(.replace))
                .animation(.dsStandard, value: entry.status)
        }
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
