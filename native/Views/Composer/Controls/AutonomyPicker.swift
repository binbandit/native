import ACP
import NativeCommands
import SwiftUI

/// The autonomy pill's popover: every permission mode the agent offers, least to most autonomous,
/// each with what the agent may do without asking. The current one is checked (dimmed while the
/// agent's plan mode suspends it), and the ones the organization forbids are locked. Plan Mode
/// itself is a mode, in the Mode pill. The footer has the key that steps to the next level.
struct AutonomyPicker: View {
    let setting: SelectSetting
    let levels: [SelectSetting.Choice]
    /// The level in effect, or the one Plan Mode returns to.
    let level: Int
    /// Whether Plan Mode stands in for the level.
    let isSuspended: Bool
    let agentName: String
    let onSet: (SelectSetting, String) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What \(agentName) may do without asking")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xs)
            VStack(spacing: 0) {
                ForEach(levels.indices, id: \.self) { index in
                    levelRow(levels[index], isCurrent: index == level)
                }
            }
            .padding(.horizontal, DS.Space.xs)
            SeparatorLine()
                .padding(.top, DS.Space.xs)
            footer
        }
        .padding(.bottom, DS.Space.xs)
        .frame(width: ComposerMetrics.modelPickerWidth)
    }

    private func levelRow(_ choice: SelectSetting.Choice, isCurrent: Bool) -> some View {
        let isForbidden = PolicyPermissionModes.forbids(setting.option, value: choice.value)
        let isSuspended = isSuspended && isCurrent
        return ComposerPickerRow(
            title: choice.name,
            detail: isForbidden ? "Not allowed by your organization" : AutonomySummary.summary(of: choice),
            trailing: isForbidden ? .locked : isCurrent ? .checked(dimmed: isSuspended) : .none,
            isEnabled: !isForbidden
        ) {
            onSet(setting, choice.value)
            dismiss()
        }
        .help(isSuspended ? "Resumes when Plan Mode ends" : choice.descriptionWithoutName ?? choice.name)
    }

    private var footer: some View {
        HStack {
            Text("Next level")
            Spacer()
            if let shortcut = CommandRegistry.shared.shortcut(for: .sessionNextPermissionMode) {
                Kbd(shortcut.displayString)
            }
        }
        .font(.dsCaption)
        .foregroundStyle(.dsTextTertiary)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }
}
