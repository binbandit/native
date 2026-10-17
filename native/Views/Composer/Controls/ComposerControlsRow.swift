import ACP
import SwiftUI

/// The composer's bottom row, after the reference app's: attach, model with its effort meter, autonomy, plan
/// mode and help leading; the follow-up hint and context usage trailing.
struct ComposerControlsRow: View {
    let settings: ComposerSettings
    /// The autonomy level shown while Plan Mode suspends it, and restored when Plan Mode ends.
    let resumedAutonomy: String?
    let usage: Usage?
    let followUpHint: FollowUpHint?
    @Binding var isModelPickerOpen: Bool
    let onAttach: () -> Void
    let onSet: (SelectSetting, String) -> Void
    let onCycleEffort: () -> Void
    let onCycleAutonomy: () -> Void
    let onTogglePlan: () -> Void

    var body: some View {
        ComposerControlsBar {
            Button("Attach Files", systemImage: "plus", action: onAttach)
                .labelStyle(.iconOnly)
                .buttonStyle(.pill(isSquare: true))
                .help("Attach files…")
            if settings.model != nil || settings.effort != nil {
                ModelPill(
                    model: settings.model,
                    effort: settings.effort,
                    switches: settings.modelSwitches,
                    isPickerOpen: $isModelPickerOpen,
                    onSet: onSet,
                    onCycleEffort: onCycleEffort
                )
            }
            if let autonomy = settings.autonomy, !settings.autonomyLevels.isEmpty {
                AutonomyPill(
                    setting: autonomy,
                    levels: settings.autonomyLevels,
                    level: settings.shownAutonomyLevel(resumed: resumedAutonomy),
                    isSuspended: settings.isAutonomySuspended,
                    onSet: onSet,
                    onCycle: onCycleAutonomy
                )
            }
            if let plan = settings.plan {
                Button("Plan Mode", action: onTogglePlan)
                    .buttonStyle(.pill(isOn: plan.isOn))
                    .help(plan.plan.description ?? "Plan before making changes")
                    .accessibilityAddTraits(plan.isOn ? .isSelected : [])
            }
            ForEach(settings.others, id: \.option.id) { setting in
                SettingMenuPill(setting: setting, onSet: onSet)
            }
            HelpButton()
        } trailing: {
            if let followUpHint {
                Text(followUpHint.text)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .help(followUpHint.help)
                    .transition(.opacity)
            }
            if let usage {
                UsageIndicator(usage: usage)
            }
        }
        .animation(.dsQuick, value: followUpHint)
    }
}
