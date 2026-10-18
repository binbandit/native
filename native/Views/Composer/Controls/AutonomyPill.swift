import ACP
import NativeCommands
import SwiftUI

/// An autonomy meter over the agent's permission modes; a click steps up a level, wrapping
/// back to the lowest, and a right-click picks one. When Plan Mode stands in for the permission mode,
/// the meter dims and shows the level that resumes afterwards.
struct AutonomyPill: View {
    let setting: SelectSetting
    let levels: [SelectSetting.Choice]
    let level: Int
    let isSuspended: Bool
    /// The shield in place of the word, when the composer is short of room.
    var showsIcon = false
    let onSet: (SelectSetting, String) -> Void
    let onCycle: () -> Void

    private var shown: SelectSetting.Choice {
        levels[min(level, levels.count - 1)]
    }

    /// The top level (Claude Code's Bypass permissions, Codex's Full access) skips every check.
    private var isUnchecked: Bool {
        levels.count > 2 && level == levels.count - 1
    }

    var body: some View {
        Button(action: onCycle) {
            HStack(spacing: DS.Space.md) {
                if showsIcon {
                    PillIcon("lock.shield")
                } else {
                    Text("Autonomy")
                }
                EffortBars(total: max(levels.count - 1, 1), level: level, tint: isUnchecked ? .dsDanger : .dsAccent)
            }
        }
        .buttonStyle(.pill)
        .disabled(isSuspended)
        .help(help)
        .accessibilityLabel("Autonomy: \(shown.name)")
        .accessibilityHint("Switches to the next autonomy level")
        .contextMenu {
            AutonomyLevelPicker(setting: setting, levels: levels, onSet: onSet)
                .pickerStyle(.inline)
        }
    }

    private var help: String {
        let detail = shown.description.map { "\(shown.name): \($0)" } ?? shown.name
        return isSuspended
            ? "Autonomy resumes at \(detail) when Plan Mode ends"
            : "Autonomy: \(detail). Click"
                + (CommandRegistry.shared.shortcut(for: .sessionNextPermissionMode).map {
                    " or press \($0.displayString)"
                } ?? "") + " for the next mode."
    }
}

/// The autonomy levels to pick from, the ones policy forbids shown but disabled: the pill's
/// right-click menu, and the More menu when the pill doesn't fit.
struct AutonomyLevelPicker: View {
    let setting: SelectSetting
    let levels: [SelectSetting.Choice]
    let onSet: (SelectSetting, String) -> Void

    var body: some View {
        Picker("Autonomy", selection: Binding(get: { setting.value }, set: { onSet(setting, $0) })) {
            ForEach(levels) { choice in
                let forbidden = PolicyPermissionModes.forbids(setting.option, value: choice.value)
                Text(forbidden ? "\(choice.name) (\(PolicyCenter.managedExplanation))" : choice.name)
                    .tag(choice.value)
                    .selectionDisabled(forbidden)
            }
        }
    }
}
