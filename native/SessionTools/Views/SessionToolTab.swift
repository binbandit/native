import SwiftUI

/// A tab in a place's strip: the tool's glyph, its name and what it says, selected while its pane
/// shows.
struct SessionToolTab: View {
    let title: String
    let systemImage: String
    var accessory: SessionToolFact.Accessory?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: systemImage)
                    .font(.dsCaption)
                    .foregroundStyle(isSelected ? .dsTextPrimary : .dsTextTertiary)
                Text(title)
                    .lineLimit(1)
                SessionToolFactAccessory(accessory: accessory)
            }
            .font(.dsBodyMedium)
            .foregroundStyle(isSelected || isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.md)
            .frame(height: DS.Size.controlXS)
            .background(
                isSelected ? Color.dsSelected : isHovered ? Color.dsHover : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlXS)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .trackHover($isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
