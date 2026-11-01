import ACP
import SwiftUI

/// The "…" chip for extra agent settings at every width, plus controls the row has no room for:
/// the task's mode, and at the tightest the model and autonomy too, plus keyboard shortcuts (Help ▸
/// Keyboard Shortcuts). The model picker opens from it then, so ⇧⌘E still has somewhere to show it.
struct ComposerMoreMenu: View {
    var agentName: String?
    var agentPicker: ComposerAgentPicker?
    let settings: ComposerSettings
    /// The model and autonomy are in the menu too (the row's `minimal` density).
    let includesModel: Bool
    @Binding var isModelPickerOpen: Bool
    let onSet: (SelectSetting, String) -> Void
    let mode: TaskModeControl?

    @Environment(CommandRegistry.self) private var commands
    @FocusedCommandContext private var context

    var body: some View {
        Menu {
            if includesModel {
                if settings.model != nil || settings.effort != nil || agentPicker != nil {
                    Button(
                        "Model: \(agentName.map { $0 + " · " } ?? "")\(settings.model?.shortModelName ?? "Default")…",
                        systemImage: "cpu"
                    ) {
                        isModelPickerOpen = true
                    }
                }
                if let autonomy = settings.autonomy, !settings.autonomyLevels.isEmpty {
                    AutonomyLevelPicker(setting: autonomy, levels: settings.autonomyLevels, onSet: onSet)
                }
                Divider()
            }
            if let mode {
                ModeMenu(control: mode)
            }
            ForEach(settings.others, id: \.option.id) { setting in
                Picker(setting.option.name, selection: Binding(get: { setting.value }, set: { onSet(setting, $0) })) {
                    ForEach(setting.choices) { choice in
                        Text(choice.name).tag(choice.value)
                    }
                }
            }
            Divider()
            Button("Keyboard Shortcuts", systemImage: "keyboard") {
                commands.perform(.helpKeyboardShortcuts, in: context)
            }
        } label: {
            Label("More Controls", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .pillChrome(isSquare: true, isOpen: includesModel && isModelPickerOpen)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More controls")
        .popover(isPresented: includesModel ? $isModelPickerOpen : .constant(false), arrowEdge: .top) {
            ModelPicker(
                agentPicker: agentPicker, model: settings.model, effort: settings.effort,
                switches: settings.modelSwitches, onSet: onSet
            ) {
                isModelPickerOpen = false
            }
            .dsPopoverBackground()
        }
    }
}

#if DEBUG
#Preview("More menu") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            ComposerMoreMenu(
                settings: ComposerPreviewFixtures.settings, includesModel: false, isModelPickerOpen: .constant(false),
                onSet: { _, _ in }, mode: nil)
            ComposerMoreMenu(
                settings: ComposerPreviewFixtures.settings, includesModel: true, isModelPickerOpen: .constant(false),
                onSet: { _, _ in }, mode: nil)
        }
    }
    .environment(CommandRegistry.shared)
}
#endif
