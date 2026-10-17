import ACP
import SwiftUI

/// An earlier turn's tool work as one line, "Explored 6 files, edited 3 files, ran 4 commands",
/// that opens the turn's rows back up in place.
struct TurnActivityFold: View {
    let summary: TurnSummary
    let isUnfolded: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "square.stack.3d.up")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.rowLeading)
                Text(summary.activityDescription ?? "Worked")
                    .foregroundStyle(isHovering ? .dsTextPrimary : .dsTextSecondary)
                    .lineLimit(1)
                DisclosureChevron(isExpanded: isUnfolded)
                    .opacity(isHovering || isUnfolded ? 1 : 0)
                Spacer(minLength: 0)
            }
            .font(.dsCallout)
            .padding(.vertical, DS.Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.dsHoverOut, value: isHovering)
        .accessibilityHint(isUnfolded ? "Folds the turn's tool calls" : "Shows the turn's tool calls")
    }
}
