import ACP
import SwiftUI

/// The composer's bottom row: attach, model with its effort meter, autonomy, plan
/// mode and help leading; the follow-up hint (while it fits) and context usage trailing. As room runs
/// out, labels give way to icons and controls move into a More menu (`ComposerControlDensity`).
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
    /// Other features' controls, after the composer's own (the goal pill), at the row's density.
    @ViewBuilder let extras: (ComposerControlDensity) -> Extras
    /// The context-window indicator, from the Usage feature, at the row's density.
    @ViewBuilder let context: (ComposerControlDensity) -> Context

    var body: some View {
        // The roomiest arrangement that fits. The hint goes first when room runs out, so the pills
        // never crowd it; the placeholder still says what Return does.
        ViewThatFits(in: .horizontal) {
            if followUpHint != nil {
                bar(.regular, showsHint: true)
            }
            bar(.regular)
            bar(.compact)
            bar(.overflow)
            bar(.minimal)
        }
    }

    private func bar(_ density: ComposerControlDensity, showsHint: Bool = false) -> some View {
        ComposerControlsBar {
            AttachButton(isPickingFiles: $isPickingFiles, onPick: onAttach)
            if density != .minimal, settings.model != nil || settings.effort != nil {
                ModelPill(
                    model: settings.model,
                    effort: settings.effort,
                    switches: settings.modelSwitches,
                    isPickerOpen: $isModelPickerOpen,
                    onSet: onSet,
                    onCycleEffort: onCycleEffort
                )
            }
            if density != .minimal, let autonomy = settings.autonomy, !settings.autonomyLevels.isEmpty {
                AutonomyPill(
                    setting: autonomy,
                    levels: settings.autonomyLevels,
                    level: settings.shownAutonomyLevel(resumed: resumedAutonomy),
                    isSuspended: settings.isAutonomySuspended,
                    showsIcon: density.showsIcons,
                    onSet: onSet,
                    onCycle: onCycleAutonomy
                )
            }
            if density == .regular || density == .compact {
                if let plan = settings.plan {
                    Button(action: onTogglePlan) {
                        if density.showsIcons {
                            Label("Plan Mode", systemImage: "list.bullet.clipboard")
                        } else {
                            Text("Plan Mode")
                        }
                    }
                    .buttonStyle(.pill(isOn: plan.isOn, isSquare: density.showsIcons))
                    .help(plan.plan.description ?? "Plan before making changes")
                    .accessibilityAddTraits(plan.isOn ? .isSelected : [])
                }
                ForEach(settings.others, id: \.option.id) { setting in
                    SettingMenuPill(setting: setting, onSet: onSet)
                }
            }
            extras(density)
            if density == .regular || density == .compact {
                HelpButton()
            } else {
                ComposerMoreMenu(
                    settings: settings,
                    includesModel: density == .minimal,
                    isModelPickerOpen: $isModelPickerOpen,
                    onSet: onSet,
                    onTogglePlan: onTogglePlan
                )
            }
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
            // Never squeezed into an ellipsis; a tighter density shows it as a ring instead.
            context(density)
                .fixedSize()
        }
        .animation(.dsQuick, value: followUpHint)
    }
}
