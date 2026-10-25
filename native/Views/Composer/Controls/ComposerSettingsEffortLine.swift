import ACP
import SwiftUI

/// Effort on one line under the models: its label, then every level as an equal segment to the
/// trailing edge, at any count, so no level hides in a menu.
struct ComposerSettingsEffortLine: View {
    let effort: SelectSetting
    var isEnabled = true
    var isKeyboardFocused = false
    let onSet: (String) -> Void

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        HStack(spacing: DS.Space.lg) {
            Text("Effort")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize()
            HStack(spacing: 0) {
                ForEach(effort.choices) { choice in
                    segment(choice)
                }
            }
            .padding(DS.Space.xxs)
            .frame(height: DS.ComposerSettings.segmentedHeight)
            .overlay { outer.strokeBorder(.dsBorder, lineWidth: 1) }
            .overlay {
                if isKeyboardFocused {
                    outer.inset(by: -2).strokeBorder(.dsKeyboardFocusIndicator, lineWidth: 2)
                }
            }
            .disabled(!isEnabled)
        }
        .composerSettingsTextEdge()
        .padding(.top, DS.Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Effort")
        .accessibilityValue(effort.currentName)
        .accessibilityAdjustableAction { direction in
            let levels = effort.choices
            guard let index = levels.firstIndex(where: { $0.value == effort.value }) else { return }
            let next = direction == .increment ? index + 1 : index - 1
            if levels.indices.contains(next) { onSet(levels[next].value) }
        }
    }

    private func segment(_ choice: SelectSetting.Choice) -> some View {
        let isOn = choice.value == effort.value
        return Button {
            onSet(choice.value)
        } label: {
            Text(choice.name)
                .font(isOn ? DS.ComposerSettings.segmentSelectedFont : DS.ComposerSettings.segmentFont)
                .foregroundStyle(isOn && isEnabled ? .dsTextPrimary : isEnabled ? .dsTextSecondary : .dsTextTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    isOn ? (isEnabled ? Color.dsSelected : .dsHover) : .clear,
                    in: .rect(cornerRadius: DS.Radius.small, style: .continuous)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
