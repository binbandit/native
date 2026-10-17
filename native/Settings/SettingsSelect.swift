import SwiftUI

/// the reference app's select: an outlined 32pt trigger showing the value and an up-down chevron. It opens
/// a native menu with the current value checked, which keeps keyboard and VoiceOver behavior.
struct SettingsSelect<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    let label: String
    @Binding var selection: Value
    let options: [Option]
    var width = SettingsMetrics.selectWidth

    @State private var isHovered = false

    private var selectedTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(selectedTitle)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: SettingsMetrics.chevronGlyph, weight: .medium))
                    .foregroundStyle(.dsTextSecondary)
            }
            .padding(.leading, DS.Space.lg)
            .padding(.trailing, DS.Space.md)
            .frame(width: width, height: SettingsMetrics.controlHeight)
            .background(isHovered ? Color.dsHover : Color.dsBackground, in: shape)
            .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
            .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .contentShape(.focusEffect, shape)
        .trackHover($isHovered)
        .accessibilityLabel(label)
        .accessibilityValue(selectedTitle)
    }
}
