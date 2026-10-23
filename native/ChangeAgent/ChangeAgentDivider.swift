import SwiftUI

struct ChangeAgentDivider: View {
    let agentName: String

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            Rectangle().fill(.dsBorder).frame(height: DS.AgentChange.dividerHeight)
            Text("Continued with \(agentName)")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Rectangle().fill(.dsBorder).frame(height: DS.AgentChange.dividerHeight)
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
