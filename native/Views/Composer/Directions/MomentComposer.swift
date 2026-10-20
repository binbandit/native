#if DEBUG
import ACP
import Modes
import SwiftUI

/// Direction D: one surface that changes with the moment. Drafting, it's the text and a single
/// door to the settings. While a turn runs, it leads with what the agent is doing and Stop, lists
/// what's queued, and says what Return does with a switch beside the text. When the agent needs
/// approval, the approval is the composer: what it wants to do, the answers with their keys, and
/// the text field becomes "tell it what to do instead".
struct MomentComposer<Editor: View, Sections: View, Files: View>: View {
    let parts: ComposerDirectionParts
    @ViewBuilder let editor: (String?) -> Editor
    @ViewBuilder let sections: () -> Sections
    @ViewBuilder let files: () -> Files

    /// The settings open in the surface, above the text.
    @State private var isSettingsOpen = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        let isResting = parts.approval == nil && !parts.session.canCancel
        VStack(alignment: .leading, spacing: 0) {
            if let approval = parts.approval {
                MomentApproval(parts: parts, call: approval)
                DirectionRule()
            } else if parts.session.canCancel {
                MomentRunning(parts: parts)
                DirectionRule()
            }
            Group(subviews: sections()) { subviews in
                ForEach(subviews) { subview in
                    subview
                    DirectionRule()
                }
            }
            if isResting, isSettingsOpen {
                MomentSettingsPanel(parts: parts)
                    .transition(.opacity)
                DirectionRule()
            }
            files()
            HStack(alignment: .bottom, spacing: 0) {
                editor(placeholder)
                trailing
                    .padding(DS.Space.md)
            }
            if isResting {
                MomentSettingsDoor(parts: parts, isOpen: $isSettingsOpen)
            }
        }
        .dsGlassEffect(in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(borderColor, lineWidth: 1)
        }
        .containerShape(shape)
        .animation(.dsStandard, value: parts.approval?.id)
        .animation(.dsStandard, value: isSettingsOpen)
    }

    private var borderColor: Color {
        if parts.isDropTargeted { return .dsAccent }
        return parts.approval != nil ? .dsAttention : .dsBorder
    }

    private var placeholder: String? {
        if parts.approval != nil {
            return "Or tell \(parts.agentName) what to do instead (rejects and sends)"
        }
        return nil
    }

    @ViewBuilder private var trailing: some View {
        if parts.hasContent {
            DirectionRoundButton(
                kind: parts.sendKind, isEnabled: parts.sendBlockedReason == nil || parts.approval != nil
            ) {
                parts.submit(parts.followUp)
            }
            .transition(.opacity)
        }
    }
}

/// The resting state's one control: the agent's setup in a line ("6.1 Sol · Low · Auto review"),
/// opening every setting in one place, in the surface.
private struct MomentSettingsDoor: View {
    let parts: ComposerDirectionParts
    @Binding var isOpen: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.dsCaption)
                    Text(summary)
                        .lineLimit(1)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.up")
                        .font(.dsMicro)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .buttonStyle(DirectionTextButtonStyle(rest: .dsTextSecondary))
            .help("Model, effort, autonomy and mode (⇧⌘E)")
            .accessibilityLabel("Settings: \(summary)")
            Spacer(minLength: DS.Space.md)
            Button("Attach Files", systemImage: "plus") { parts.isPickingFiles = true }
                .labelStyle(.iconOnly)
                .buttonStyle(DirectionTextButtonStyle())
                .help("Attach files… (⌘U)")
            ContextIndicator(session: parts.session, style: .ring)
        }
        .font(.dsBody)
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.md)
        .onChange(of: parts.isModelPickerOpen) { _, isRequested in
            if isRequested {
                isOpen = true
                parts.isModelPickerOpen = false
            }
        }
    }

    private var summary: String {
        var facts = [parts.modelName, parts.effortName, parts.autonomyName].compactMap(\.self)
        if parts.mode.current.id != .build {
            facts.append(parts.mode.current.name)
        }
        return facts.joined(separator: " · ")
    }
}

/// Every setting in one place, in the surface: a row each, its values to pick from.
private struct MomentSettingsPanel: View {
    let parts: ComposerDirectionParts

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(CommandLineSettingQuery.Command.allCases, id: \.self) { command in
                let choices = CommandLineSettingQuery.all(
                    command, settings: parts.settings, mode: parts.mode, resumedAutonomy: parts.resumedAutonomy)
                if !choices.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                        Text(command.rawValue.capitalized)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                            .frame(width: DS.Size.popoverWidth / 5, alignment: .leading)
                        FlowLayout(spacing: DS.Space.xxs) {
                            ForEach(choices) { choice in
                                Button(choice.name.directionShortName) { parts.applyChoice(choice) }
                                    .buttonStyle(DirectionChoiceStyle(isCurrent: choice.isCurrent))
                                    .help(choice.detail ?? choice.name)
                            }
                        }
                    }
                }
            }
            HStack(spacing: DS.Space.md) {
                Text("Session")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.popoverWidth / 5, alignment: .leading)
                MCPComposerChip(session: parts.session, showsCount: true)
                ContextIndicator(session: parts.session, style: .labeled)
            }
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// While a turn runs: what the agent is doing and for how long, Stop, what's queued, and what
/// Return does with the next message.
private struct MomentRunning: View {
    let parts: ComposerDirectionParts

    @AppStorage(FollowUpBehavior.storageKey) private var followUp = FollowUpBehavior.defaultValue

    var body: some View {
        let activity = ComposerTurnActivity(session: parts.session)
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .typing)
                    .frame(width: DS.Space.lg, height: DS.Space.lg)
                Image(systemName: activity.glyph)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                Text(activity.line)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let start = activity.startedAt {
                    ElapsedTimeText(since: start)
                        .monospacedDigit()
                        .foregroundStyle(.dsTextTertiary)
                }
                Spacer(minLength: DS.Space.lg)
                if parts.session.supportsSteering {
                    // What Return does with the next message, as a choice rather than a hint.
                    HStack(spacing: DS.Space.xxs) {
                        Text("↩")
                            .foregroundStyle(.dsTextTertiary)
                            .padding(.horizontal, DS.Space.xs)
                        ForEach([FollowUpBehavior.steer, .queue], id: \.self) { behavior in
                            Button(behavior.title) { followUp = behavior }
                                .buttonStyle(DirectionChoiceStyle(isCurrent: followUp == behavior))
                        }
                    }
                    .help(
                        "What Return does with your next message while \(parts.agentName) works; ⌘Return does the other"
                    )
                }
                Button(action: parts.stop) {
                    HStack(spacing: DS.Space.xs) {
                        Text("Stop")
                        Kbd("esc")
                    }
                }
                .buttonStyle(.ds(.secondary, size: .small))
            }
            ForEach(Array(parts.session.queuedPrompts.enumerated()), id: \.element.id) { index, prompt in
                HStack(spacing: DS.Space.md) {
                    Text(index == 0 ? "Next" : "Then")
                        .foregroundStyle(.dsTextTertiary)
                        .frame(width: DS.Space.xxxl, alignment: .leading)
                    Text(prompt.text)
                        .foregroundStyle(.dsTextSecondary)
                        .lineLimit(1)
                        .onTapGesture { parts.edit(prompt) }
                    Spacer(minLength: DS.Space.md)
                    if parts.session.sendNowRoute != nil {
                        Button("Send now") { parts.sendNow(prompt.id) }
                            .buttonStyle(DirectionTextButtonStyle())
                    }
                    Button("Remove", systemImage: "xmark") { parts.remove(prompt.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(DirectionTextButtonStyle())
                }
                .padding(.leading, DS.Space.xxl + DS.Space.xs)
            }
        }
        .font(.dsBody)
        .padding(DS.Space.lg)
    }
}

/// The approval as the composer: what the agent wants to do, in full, and the answers with their keys.
private struct MomentApproval: View {
    let parts: ComposerDirectionParts
    let call: ToolCallState

    var body: some View {
        let summary = ComposerApprovalSummary(call)
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.sm) {
                DirectionAttentionDot()
                Text("\(parts.agentName) wants to \(summary.verb.lowercased()) \(summary.subject)")
                    .font(.dsCalloutMedium)
                    .foregroundStyle(.dsTextPrimary)
                Spacer(minLength: DS.Space.md)
                Text(parts.session.cwd.abbreviatedPath)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(summary.command ?? summary.subject)
                .codeTextStyle(.compact)
                .foregroundStyle(.dsTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.md)
                .background(.dsCodeBlockBackground, in: RoundedRectangle(cornerRadius: DS.Radius.control))
            HStack(spacing: DS.Space.md) {
                ForEach(call.permission?.options ?? []) { option in
                    answer(option)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(DS.Space.lg)
    }

    @ViewBuilder
    private func answer(_ option: PermissionOption) -> some View {
        let button = Button {
            parts.answer(option, for: call)
        } label: {
            HStack(spacing: DS.Space.sm) {
                Text(option.name)
                if let key = Self.key(for: option.kind) {
                    Text(key)
                        .font(.dsMonoCaption)
                        .opacity(0.7)
                }
            }
        }
        .keyboardShortcut(Self.shortcut(for: option.kind))
        switch option.kind {
        case .allowOnce: button.buttonStyle(.ds(.primary, size: .medium))
        case .rejectOnce, .rejectAlways: button.buttonStyle(.ds(.secondary, size: .medium))
        case .allowAlways: button.buttonStyle(.ds(.secondary, size: .medium))
        }
    }

    private static func key(for kind: PermissionOption.Kind) -> String? {
        switch kind {
        case .allowOnce: "⌘Y"
        case .allowAlways: "⌥⌘Y"
        case .rejectOnce: "⌘⇧⌫"
        case .rejectAlways: nil
        }
    }

    private static func shortcut(for kind: PermissionOption.Kind) -> KeyboardShortcut? {
        switch kind {
        case .allowOnce: KeyboardShortcut("y", modifiers: .command)
        case .allowAlways: KeyboardShortcut("y", modifiers: [.command, .option])
        case .rejectOnce: KeyboardShortcut(.delete, modifiers: [.command, .shift])
        case .rejectAlways: nil
        }
    }
}
#endif
