import SwiftUI

struct ChangeAgentDivider: View {
    let agentName: String
    var modelName: String?
    var isReversed = false
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            Rectangle().fill(.dsSeparator).frame(height: DS.AgentChange.dividerHeight)
            Text("\(isReversed ? "Returned to" : "Continued with") \(agentName)\(modelName.map { " · " + $0 } ?? "")")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if let onUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(.plain)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .dsHitTarget(DS.ComposerSettings.controlHeight)
                    .accessibilityLabel("Undo Change to \(agentName)")
            }
            Rectangle().fill(.dsSeparator).frame(height: DS.AgentChange.dividerHeight)
        }
        .padding(.vertical, DS.Space.lg)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Change Agent - Transcript divider") {
    DSPreviewPair { ChangeAgentDivider(agentName: "Example Agent").frame(width: DS.Size.contentColumn) }
}
#endif
