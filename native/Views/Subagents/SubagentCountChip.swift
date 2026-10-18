import ACP
import SwiftUI

/// "2 agents ›" at the end of a turn that started subagents. One agent opens straight into the
/// inspector (⌥⌘I); several list first, each with what it's doing now.
struct SubagentCountChip: View {
    let subagents: [SubagentState]
    let open: (SessionID) -> Void

    @State private var isListing = false

    var body: some View {
        Button {
            if subagents.count == 1, let only = subagents.first {
                open(only.id)
            } else {
                isListing = true
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "person.2")
                    .symbolRenderingMode(.hierarchical)
                Text(subagents.count == 1 ? "1 agent" : "\(subagents.count) agents")
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.dsMicro.weight(.semibold))
                    .foregroundStyle(.dsTextQuaternary)
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xxs)
            .background(.dsHover, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(subagents.count == 1 ? "Show this subagent's conversation" : "Show the subagents this turn started")
        .popover(isPresented: $isListing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(subagents) { subagent in
                    Button {
                        isListing = false
                        open(subagent.id)
                    } label: {
                        HStack(spacing: DS.Space.md) {
                            Text(subagent.title ?? "Subagent")
                                .font(.dsCalloutMedium)
                                .foregroundStyle(.dsTextPrimary)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.lg)
                            SubagentStatusLabel(state: subagent.workState)
                        }
                        .padding(.horizontal, DS.Space.md)
                        .frame(minHeight: DS.Size.listRow)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.Space.sm)
            .frame(minWidth: DS.Size.contentColumn / 3)
            .dsPopoverBackground()
        }
    }
}
