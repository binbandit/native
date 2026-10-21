import SwiftUI

/// The folded tail stays in the project's own order and has an explicit way back to the calm list.
struct SidebarNextDisclosureRow: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.dsMicro)
                    .frame(width: DS.Size.rowLeading)
                Text(title)
                    .font(.dsCaption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? .dsTextSecondary : .dsTextTertiary)
            .padding(.horizontal, DS.Space.sm)
            .frame(minHeight: DS.Size.rowMinHeight)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .trackHover($isHovered)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

#if DEBUG
#Preview("Quiet projects - More and less") {
    DSPreviewPair {
        VStack {
            SidebarNextDisclosureRow(title: "12 more", isExpanded: false) {}
            SidebarNextDisclosureRow(title: "Show less", isExpanded: true) {}
        }
        .frame(width: DS.Size.sidebarWidth)
    }
}
#endif
