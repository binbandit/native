import ACP
import SwiftUI

/// A short setting list, including the agent's descriptions and the current selection.
struct ComposerNextSettingPicker: View {
    let setting: SelectSetting
    let onSet: (SelectSetting, String) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(setting.option.name)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.sm)
            CappedHeightScrollView(maxHeight: ComposerMetrics.modelListMaxHeight) {
                VStack(spacing: 0) {
                    ForEach(setting.choices) { choice in
                        ComposerPickerRow(
                            title: choice.name,
                            detail: setting.option.category == "thought_level"
                                ? setting.effortNote(for: choice) ?? choice.descriptionWithoutName
                                : choice.descriptionWithoutName,
                            trailing: choice.value == setting.value ? .checked(dimmed: false) : .none,
                            isEnabled: true
                        ) {
                            onSet(setting, choice.value)
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding(DS.Space.xs)
        .frame(width: ComposerMetrics.modelPickerWidth)
    }
}

#if DEBUG
#Preview("Quiet setting picker - Effort") {
    DSPreviewPair {
        if let effort = ComposerPreviewFixtures.settings.effort {
            ComposerNextSettingPicker(setting: effort, onSet: { _, _ in }, dismiss: {})
                .dsPopoverBackground()
        }
    }
}

#Preview("Quiet setting picker - Additional agent option") {
    DSPreviewPair {
        if let setting = ComposerPreviewFixtures.settings.others.first {
            ComposerNextSettingPicker(setting: setting, onSet: { _, _ in }, dismiss: {})
                .dsPopoverBackground()
        }
    }
}
#endif
