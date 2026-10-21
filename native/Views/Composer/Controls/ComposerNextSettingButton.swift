import ACP
import SwiftUI

/// Agent-defined settings keep their own names, with the same plain-word entry as known settings.
struct ComposerNextSettingButton: View {
    let setting: SelectSetting
    let onSet: (SelectSetting, String) -> Void
    @State private var isOpen = false

    var body: some View {
        Button("\(setting.option.name): \(setting.currentName)") { isOpen.toggle() }
            .buttonStyle(ComposerFactButtonStyle())
            .accessibilityLabel("\(setting.option.name): \(setting.currentName)")
            .help("Change \(setting.option.name)")
            .popover(isPresented: $isOpen, arrowEdge: .top) {
                ComposerNextSettingPicker(setting: setting, onSet: onSet) { isOpen = false }
                    .dsPopoverBackground()
            }
    }
}

#if DEBUG
#Preview("Quiet setting - Additional agent option") {
    DSPreviewPair {
        if let setting = ComposerPreviewFixtures.settings.others.first {
            ComposerNextSettingButton(setting: setting, onSet: { _, _ in })
        }
    }
}
#endif
