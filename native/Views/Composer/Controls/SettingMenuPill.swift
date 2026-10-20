import ACP
import SwiftUI

/// Any other setting the agent offers, as a plain menu chip.
struct SettingMenuPill: View {
    let setting: SelectSetting
    let onSet: (SelectSetting, String) -> Void

    var body: some View {
        PillMenu("\(setting.option.name): \(setting.currentName)") {
            Picker(setting.option.name, selection: Binding(get: { setting.value }, set: { onSet(setting, $0) })) {
                ForEach(setting.choices) { choice in
                    Text(choice.name).tag(choice.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .help(setting.option.description ?? setting.option.name)
    }
}

#if DEBUG
#Preview("Setting menu pill") {
    DSPreviewPair {
        HStack {
            ForEach(ComposerPreviewFixtures.settings.others, id: \.option.id) { setting in
                SettingMenuPill(setting: setting, onSet: { _, _ in })
            }
        }
    }
}
#endif
