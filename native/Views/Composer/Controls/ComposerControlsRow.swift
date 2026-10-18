import ACP
import SwiftUI

/// The composer's bottom row, after the reference app's: attach, model with its effort meter, autonomy, plan
/// mode and help leading; the follow-up hint (while it fits) and context usage trailing.
struct ComposerControlsRow<Extras: View, Context: View>: View {
    let settings: ComposerSettings
    /// The autonomy level shown while Plan Mode suspends it, and restored when Plan Mode ends.
    let resumedAutonomy: String?
    /// What Return and ⌘Return do with a follow-up, shown while the agent works.
    let followUpHint: FollowUpHint?
    @Binding var isModelPickerOpen: Bool
    /// The "+" chip's file picker, which File ▸ Attach Files… opens too.
    @Binding var isPickingFiles: Bool
    let onAttach: (IncomingAttachments) -> Void
    let onSet: (SelectSetting, String) -> Void
    let onCycleEffort: () -> Void
    let onCycleAutonomy: () -> Void
    let onTogglePlan: () -> Void
    /// Other features' controls, after the composer's own (the goal pill).
    @ViewBuilder let extras: () -> Extras
    /// The context-window indicator, from the Usage feature.
    @ViewBuilder let context: () -> Context

    var body: some View {
        if followUpHint != nil {
            // The hint goes first when room runs out, so the pills never crowd it; the placeholder
            // still says what Return does.
            ViewThatFits(in: .horizontal) {
                bar(showsHint: true)
                bar(showsHint: false)
            }
        } else {
            bar(showsHint: false)
        }
    }

    private func bar(showsHint: Bool) -> some View {
        ComposerControlsBar {
            AttachButton(isPickingFiles: $isPickingFiles, onPick: onAttach)
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
            extras()
            HelpButton()
        } trailing: {
            if showsHint, let followUpHint {
                Text(followUpHint.text)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .help(followUpHint.help)
                    .transition(.opacity)
            }
            // Never squeezed into an ellipsis; the pills scroll instead.
            context()
                .fixedSize()
        }
        .animation(.dsQuick, value: followUpHint)
    }
}
