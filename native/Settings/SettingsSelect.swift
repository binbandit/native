import SwiftUI

/// A select: an outlined 32pt trigger showing the value and an up-down chevron. It opens
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
    var fieldStyle = false
    var isDefault = false

    @Environment(\.settingsPlainly) private var plainly

    @Environment(\.settingsRowTitle) private var rowTitle
    @Environment(\.isEnabled) private var isEnabled
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
                    .foregroundStyle(plainly && isDefault ? Color.dsTextSecondary : .dsTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: plainly && !fieldStyle ? .trailing : .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: SettingsMetrics.chevronGlyph, weight: .medium))
                    .foregroundStyle(.dsTextSecondary)
            }
            .padding(.leading, DS.Space.lg)
            .padding(.trailing, DS.Space.md)
            .frame(width: width, height: plainly ? DS.Settings.controlHeight : SettingsMetrics.controlHeight)
            .background(
                isHovered && isEnabled ? Color.dsHover : plainly && !fieldStyle ? .clear : .dsBackground, in: shape
            )
            .overlay {
                if !plainly || fieldStyle { shape.strokeBorder(.dsBorder, lineWidth: DS.Settings.hairline) }
            }
            .contentShape(shape)
            // Half strength while disabled, the same as the switch and buttons.
            .opacity(isEnabled ? 1 : 0.5)
        }
        .menuStyle(.button)
        .buttonStyle(SettingsSelectButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .settingsFocusShape(shape)
        .trackHover($isHovered)
        .accessibilityLabel(rowTitle ?? label)
        .accessibilityValue(selectedTitle)
    }
}

/// No pressed or disabled styling of its own: the select draws both.
private struct SettingsSelectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#if DEBUG
#Preview("Select") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSelect(
                label: "Follow-up behavior", selection: .constant(FollowUpBehavior.steer),
                options: FollowUpBehavior.allCases.map { .init(value: $0, title: $0.title) })
            SettingsSelect(
                label: "Default model", selection: .constant("opus"),
                options: [.init(value: "opus", title: "Last used (Opus 5.5, with a long name that truncates)")])
            SettingsSelect(
                label: "Default effort", selection: .constant("high"), options: [.init(value: "high", title: "High")]
            )
            .disabled(true)
        }
    }
}
#endif
