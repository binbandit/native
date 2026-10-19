import ACP
import SwiftUI

/// The "…" chip that takes the controls the row has no room for: Plan Mode and the agent's other
/// settings, and at the tightest the model and autonomy too, plus the keyboard shortcuts (Help ▸
/// Keyboard Shortcuts). The model picker opens from it then, so ⇧⌘E still has somewhere to show it.
struct ComposerMoreMenu: View {
    let settings: ComposerSettings
    /// The model and autonomy are in the menu too (the row's `minimal` density).
    let includesModel: Bool
    @Binding var isModelPickerOpen: Bool
    let onSet: (SelectSetting, String) -> Void
    let onTogglePlan: () -> Void

    @Environment(CommandRegistry.self) private var commands
    @FocusedCommandContext private var context

    var body: some View {
        Menu {
            if includesModel {
                if settings.model != nil || settings.effort != nil {
                    Button("Model: \(settings.model?.shortModelName ?? "Default")…", systemImage: "cpu") {
                        isModelPickerOpen = true
                    }
                }
                if let autonomy = settings.autonomy, !settings.autonomyLevels.isEmpty {
                    AutonomyLevelPicker(setting: autonomy, levels: settings.autonomyLevels, onSet: onSet)
                }
                Divider()
            }
            if let plan = settings.plan {
                Toggle("Plan Mode", isOn: Binding(get: { plan.isOn }, set: { _ in onTogglePlan() }))
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
            ModelPicker(model: settings.model, effort: settings.effort, switches: settings.modelSwitches, onSet: onSet)
            {
                isModelPickerOpen = false
            }
            .dsPopoverBackground()
        }
    }
}
