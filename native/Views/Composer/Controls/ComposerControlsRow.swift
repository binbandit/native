import ACP
import SwiftUI

/// The composer's bottom row: attach, model with its effort meter, autonomy and the task's mode
/// leading; contextual editing keys (while they fit) and context usage trailing. As room runs
/// out, labels give way to icons and controls move into a More menu (`ComposerControlDensity`).
struct ComposerControlsRow<Extras: View, Context: View>: View {
    let settings: ComposerSettings
    let agentName: String
    /// The autonomy level shown while Plan Mode suspends it, and restored when Plan Mode ends.
    let resumedAutonomy: String?
    /// Keys for a code block or queued-message edit.
    let followUpHint: FollowUpHint?
    @Binding var isModelPickerOpen: Bool
    /// The "+" chip's file picker, which File ▸ Attach Files… opens too.
    @Binding var isPickingFiles: Bool
    let onAttach: (IncomingAttachments) -> Void
    let onSet: (SelectSetting, String) -> Void
    let onCycleEffort: () -> Void
    /// The task's mode (Build, Plan, Ask…), from the Modes feature.
    let mode: TaskModeControl?
    /// Other features' controls, after the composer's own (the goal pill), at the row's density.
    @ViewBuilder let extras: (ComposerControlDensity) -> Extras
    /// The context-window indicator, from the Usage feature, at the row's density.
    @ViewBuilder let context: (ComposerControlDensity) -> Context

    var body: some View {
        // The roomiest arrangement that fits. The hint goes first when room runs out, so the pills
        // never crowd it.
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
                    agentName: agentName,
                    showsIcon: density.showsIcons,
                    onSet: onSet
                )
            }
            if density == .regular || density == .compact {
                if let mode {
                    ModePill(control: mode, showsIcon: density.showsIcons)
                }
                ForEach(settings.others, id: \.option.id) { setting in
                    SettingMenuPill(setting: setting, onSet: onSet)
                }
            }
            extras(density)
            if density == .overflow || density == .minimal {
                ComposerMoreMenu(
                    settings: settings,
                    includesModel: density == .minimal,
                    isModelPickerOpen: $isModelPickerOpen,
                    onSet: onSet,
                    mode: mode
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

#if DEBUG
#Preview("Controls row - Widths") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            // Regular with code-block keys, then each density as room runs out.
            ForEach([680, 560, 420, 300, 220], id: \.self) { width in
                ComposerSurface {
                    ComposerControlsRowPreview(
                        settings: ComposerPreviewFixtures.settings,
                        hint: width == 680
                            ? .inCodeBlock(primary: "Send", explanation: "Send the message.") : nil)
                }
                .frame(width: CGFloat(width))
            }
        }
    }
    .environment(CommandRegistry.shared)
}

#Preview("Controls row - Plan Mode") {
    DSPreviewPair {
        ComposerSurface {
            ComposerControlsRowPreview(settings: ComposerPreviewFixtures.planModeSettings, hint: nil)
        }
        .frame(width: 560)
    }
    .environment(CommandRegistry.shared)
}

/// The row with inert actions and the context ring the Usage feature puts there.
private struct ComposerControlsRowPreview: View {
    let settings: ComposerSettings
    let hint: FollowUpHint?

    var body: some View {
        ComposerControlsRow(
            settings: settings, agentName: "Claude Code", resumedAutonomy: "auto", followUpHint: hint,
            isModelPickerOpen: .constant(false), isPickingFiles: .constant(false), onAttach: { _ in },
            onSet: { _, _ in }, onCycleEffort: {}, mode: nil, extras: { _ in EmptyView() },
            context: { _ in ContextUsageRing(fraction: 0.42) }
        )
    }
}
#endif
