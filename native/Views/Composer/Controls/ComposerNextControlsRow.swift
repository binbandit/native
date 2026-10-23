import ACP
import Modes
import NativeCommands
import SwiftUI

/// Direction A at rest: settings read as a sentence; each word opens the existing picker.
/// The line scrolls at narrow widths so full names and every action remain reachable.
struct ComposerNextControlsRow<Extras: View, Context: View>: View {
    let settings: ComposerSettings
    let agentName: String
    var changesAgent = false
    let resumedAutonomy: String?
    var followUpHint: FollowUpHint? = nil
    @Binding var isModelPickerOpen: Bool
    @Binding var isPickingFiles: Bool
    let onAttach: (IncomingAttachments) -> Void
    let onSet: (SelectSetting, String) -> Void
    let onChooseAgent: () -> Void
    let mode: TaskModeControl?
    @ViewBuilder let extras: () -> Extras
    @ViewBuilder let context: () -> Context

    @State private var isEffortOpen = false
    @State private var isAutonomyOpen = false
    @State private var isModeOpen = false

    var body: some View {
        ComposerControlsBar {
            AttachButton(isPickingFiles: $isPickingFiles, onPick: onAttach, isQuiet: true)
            HStack(spacing: DS.Space.xs) {
                Button(agentName, action: onChooseAgent)
                    .buttonStyle(ComposerFactButtonStyle())
                    .accessibilityLabel("Agent: \(agentName)")
                    .help(
                        changesAgent
                            ? "Change this task to another agent"
                            : CommandRegistry.shared.help("New task with another agent", for: .sessionNewWithAgent))
                if settings.model != nil || !settings.modelSwitches.isEmpty {
                    separator
                    model
                }
                if let effort = settings.effort {
                    separator
                    effortButton(effort)
                }
                if let autonomy = settings.autonomy, !settings.autonomyLevels.isEmpty {
                    separator
                    autonomyButton(autonomy)
                }
                if let mode {
                    separator
                    modeButton(mode)
                }
                ForEach(settings.others, id: \.option.id) { setting in
                    separator
                    ComposerNextSettingButton(setting: setting, onSet: onSet)
                }
            }
            extras()
        } trailing: {
            ViewThatFits(in: .horizontal) {
                if let followUpHint {
                    HStack(spacing: DS.Space.md) {
                        Text(followUpHint.text)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                            .fixedSize()
                            .help(followUpHint.help)
                        context().fixedSize()
                    }
                }
                context().fixedSize()
            }
        }
    }

    private var separator: some View {
        Text("·")
            .font(.dsBody)
            .foregroundStyle(.dsTextQuaternary)
            .accessibilityHidden(true)
    }

    private var model: some View {
        Button {
            isModelPickerOpen.toggle()
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(settings.model?.shortModelName ?? "Model")
                if settings.modelSwitches.contains(where: \.isOn) {
                    Image(systemName: "bolt.fill").font(.dsMicro)
                }
            }
        }
        .buttonStyle(ComposerFactButtonStyle())
        .accessibilityLabel("Model: \(settings.model?.currentName ?? "Default")")
        .help(CommandRegistry.shared.help("Change model", for: .sessionChooseModel))
        .popover(isPresented: $isModelPickerOpen, arrowEdge: .top) {
            ModelPicker(
                model: settings.model, effort: settings.effort, switches: settings.modelSwitches, onSet: onSet
            ) {
                isModelPickerOpen = false
            }
            .dsPopoverBackground()
        }
    }

    private func effortButton(_ effort: SelectSetting) -> some View {
        Button("\(effort.currentName) effort") { isEffortOpen.toggle() }
            .buttonStyle(ComposerFactButtonStyle())
            .accessibilityLabel("Effort: \(effort.currentName)")
            .help("Change effort")
            .popover(isPresented: $isEffortOpen, arrowEdge: .top) {
                ComposerNextSettingPicker(setting: effort, onSet: onSet) { isEffortOpen = false }
                    .dsPopoverBackground()
            }
            // Effort-only agents still answer the existing Model picker command.
            .popover(
                isPresented: settings.model == nil && settings.modelSwitches.isEmpty
                    ? $isModelPickerOpen : .constant(false), arrowEdge: .top
            ) {
                ModelPicker(model: nil, effort: effort, switches: [], onSet: onSet) { isModelPickerOpen = false }
                    .dsPopoverBackground()
            }
    }

    private func autonomyButton(_ setting: SelectSetting) -> some View {
        let levels = settings.autonomyLevels
        let level = settings.shownAutonomyLevel(resumed: resumedAutonomy)
        let name = levels[level].name
        return Button(settings.isAutonomySuspended ? "\(name) after Plan" : name) { isAutonomyOpen.toggle() }
            .buttonStyle(ComposerFactButtonStyle())
            .accessibilityLabel("Autonomy: \(name)\(settings.isAutonomySuspended ? ", resumes after Plan" : "")")
            .help(cycleHelp("Change autonomy", command: .sessionNextPermissionMode, next: "level"))
            .popover(isPresented: $isAutonomyOpen, arrowEdge: .top) {
                AutonomyPicker(
                    setting: setting, levels: levels, level: level, isSuspended: settings.isAutonomySuspended,
                    agentName: agentName, onSet: onSet
                ) { isAutonomyOpen = false }
                .dsPopoverBackground()
            }
    }

    private func modeButton(_ control: TaskModeControl) -> some View {
        Button(control.current.name) { isModeOpen.toggle() }
            .buttonStyle(ComposerFactButtonStyle())
            .accessibilityLabel("Mode: \(control.current.name)")
            .help(cycleHelp("Change mode", command: .sessionNextMode, next: "mode"))
            .popover(isPresented: $isModeOpen, arrowEdge: .top) {
                ModePicker(control: control) { isModeOpen = false }
                    .dsPopoverBackground()
            }
    }

    private func cycleHelp(_ text: String, command: NativeCommand.ID, next: String) -> String {
        guard let shortcut = CommandRegistry.shared.shortcut(for: command) else { return text }
        return "\(text). Press \(shortcut.displayString) for the next \(next)."
    }
}

#if DEBUG
#Preview("Quiet composer - Empty and typing") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerNextPreviewFixtures.surface()
            ComposerNextPreviewFixtures.surface(draft: "Explain how the composer handles attachments.")
        }
        .frame(width: 760)
    }
}

#Preview("Quiet composer - Narrow, long names and missing settings") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerNextPreviewFixtures.surface(agent: "A team agent with a long display name")
            ComposerNextPreviewFixtures.surface(settings: ComposerSettings([]))
            ComposerNextPreviewFixtures.surface(settings: ComposerPreviewFixtures.planModeSettings)
        }
        .frame(width: 300)
    }
}

#Preview("Quiet composer - Disconnected") {
    DSPreviewPair {
        ComposerNextPreviewFixtures.surface(draft: "The draft stays here while disconnected.")
            .disabled(true)
            .frame(width: 760)
    }
}
#endif
