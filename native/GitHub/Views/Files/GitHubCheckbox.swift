import SwiftUI

/// A checkbox drawn the same on the Mac and iPad (the system checkbox style is Mac-only).
struct GitHubCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: DS.Size.navIcon + DS.Space.xxs))
                    .foregroundStyle(isOn ? Color.dsAccent : isHovered ? .dsTextSecondary : .dsTextTertiary)
                Text(title)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
            }
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlXS)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
