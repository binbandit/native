import ACP
import NativeCommands
import SwiftUI

/// The agent's permission mode: its name and an autonomy meter, or just the meter (with a shield)
/// when the composer is short of room. A click opens `AutonomyPicker`, listing every level with what
/// the agent may do without asking; ⇧⌘M steps to the next. When Plan Mode stands in for the
/// permission mode (a mode that uses it), the meter dims and shows the level that resumes afterwards.
struct AutonomyPill: View {
    let setting: SelectSetting
    let levels: [SelectSetting.Choice]
    let level: Int
    let isSuspended: Bool
    let agentName: String
    /// The shield in place of the name, when the composer is short of room.
    var showsIcon = false
    let onSet: (SelectSetting, String) -> Void

    @State private var isPickerOpen = false

    private var shown: SelectSetting.Choice {
        levels[min(level, levels.count - 1)]
    }

    /// The top level (Claude Code's Bypass permissions, Codex's Full access) skips every check.
    private var isUnchecked: Bool {
        levels.count > 2 && level == levels.count - 1
    }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            HStack(spacing: DS.Space.md) {
                if showsIcon {
                    PillIcon("lock.shield")
                } else {
                    Text(shown.name)
                        .foregroundStyle(isSuspended ? .dsTextTertiary : .dsTextPrimary)
                }
                EffortBars(
                    total: max(levels.count - 1, 1), level: level, isMuted: isSuspended,
                    tint: isUnchecked ? .dsDanger : .dsAccent)
            }
        }
        .buttonStyle(.pill(isOpen: isPickerOpen))
        .help(help)
        .accessibilityLabel("Autonomy: \(shown.name)")
        .accessibilityHint("Shows the autonomy levels")
        .popover(isPresented: $isPickerOpen, arrowEdge: .top) {
            AutonomyPicker(
                setting: setting, levels: levels, level: level, isSuspended: isSuspended, agentName: agentName,
                onSet: onSet
            ) {
                isPickerOpen = false
            }
            .dsPopoverBackground()
        }
    }

    private var help: String {
        let detail = AutonomySummary.summary(of: shown).map { "\(shown.name): \($0)" } ?? shown.name
        let next = CommandRegistry.shared.shortcut(for: .sessionNextPermissionMode).map {
            " Press \($0.displayString) for the next level."
        }
        return isSuspended
            ? "Autonomy resumes at \(detail) when Plan Mode ends"
            : "Autonomy: \(detail).\(next ?? "")"
    }
}

/// The autonomy levels as a submenu, each with what the agent may do without asking, and the ones
/// policy forbids shown but disabled: the More menu's stand-in for the pill when it doesn't fit.
struct AutonomyLevelPicker: View {
    let setting: SelectSetting
    let levels: [SelectSetting.Choice]
    let onSet: (SelectSetting, String) -> Void

    var body: some View {
        Menu("Autonomy", systemImage: "lock.shield") {
            ForEach(levels) { choice in
                let forbidden = PolicyPermissionModes.forbids(setting.option, value: choice.value)
                Toggle(
                    isOn: Binding(get: { choice.value == setting.value }, set: { _ in onSet(setting, choice.value) })
                ) {
                    Text(choice.name)
                    if let detail = forbidden ? "Not allowed by your organization" : AutonomySummary.summary(of: choice)
                    {
                        Text(detail)
                    }
                }
                .disabled(forbidden)
            }
        }
    }
}

#if DEBUG
#Preview("Autonomy pill") {
    let settings = ComposerPreviewFixtures.settings
    let plan = ComposerPreviewFixtures.planModeSettings
    DSPreviewPair {
        if let autonomy = settings.autonomy, let suspended = plan.autonomy {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                // Every level, least to most autonomous; the last skips every check.
                ForEach(settings.autonomyLevels.indices, id: \.self) { level in
                    AutonomyPill(
                        setting: autonomy, levels: settings.autonomyLevels, level: level, isSuspended: false,
                        agentName: "Claude Code", onSet: { _, _ in })
                }
                AutonomyPill(
                    setting: autonomy, levels: settings.autonomyLevels, level: 1, isSuspended: false,
                    agentName: "Claude Code", showsIcon: true, onSet: { _, _ in })
                AutonomyPill(
                    setting: suspended, levels: plan.autonomyLevels, level: plan.shownAutonomyLevel(resumed: "auto"),
                    isSuspended: true, agentName: "Claude Code", onSet: { _, _ in })
            }
        }
    }
}
#endif
