#if DEBUG
import ACP
import Modes
import SwiftUI

/// Direction A: just the text. The settings are one line of plain facts under it ("6.1 Sol · Low
/// effort · Auto review"), each opening its values in place of the line; the line turns into the
/// turn's status while the agent works, and into what it waits for when it waits. No outlines, no
/// pills: the one filled control is Send.
struct QuietComposer<Editor: View, Sections: View, Files: View>: View {
    let parts: ComposerDirectionParts
    @ViewBuilder let editor: (String?) -> Editor
    @ViewBuilder let sections: () -> Sections
    @ViewBuilder let files: () -> Files

    /// The fact whose values show in place of the line.
    @State private var openFact: CommandLineSettingQuery.Command?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: sections()) { subviews in
                ForEach(subviews) { subview in
                    subview
                    DirectionRule()
                }
            }
            QuietQueue(parts: parts)
            files()
            editor(nil)
                .padding(.top, DS.Space.xs)
            footer
        }
        .dsGlassEffect(in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(parts.isDropTargeted ? Color.dsAccent : .dsSeparator, lineWidth: 1)
        }
        .containerShape(shape)
        .animation(.dsQuick, value: openFact)
        .onChange(of: parts.isModelPickerOpen) { _, isOpen in
            // ⇧⌘E opens the model's values in place.
            if isOpen {
                openFact = .model
                parts.isModelPickerOpen = false
            }
        }
    }

    // MARK: - The line

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            if let openFact {
                QuietChooser(parts: parts, command: openFact) { self.openFact = nil }
            } else {
                leading
                Spacer(minLength: DS.Space.lg)
                trailing
            }
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextTertiary)
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.md)
        .frame(minHeight: DS.Size.composerPill)
    }

    @ViewBuilder private var leading: some View {
        if parts.approval != nil {
            HStack(spacing: DS.Space.sm) {
                DirectionAttentionDot()
                Text("\(parts.agentName) is waiting for your approval above")
                    .foregroundStyle(.dsTextSecondary)
            }
        } else if parts.session.canCancel {
            let activity = ComposerTurnActivity(session: parts.session)
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .typing)
                    .frame(width: DS.Space.lg, height: DS.Space.lg)
                Text(activity.line)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let start = activity.startedAt {
                    ElapsedTimeText(since: start)
                        .monospacedDigit()
                }
            }
        } else {
            facts
        }
    }

    /// The settings as words: the model, its effort, the autonomy, and the mode when it isn't Build.
    private var facts: some View {
        HStack(spacing: DS.Space.xs) {
            Button("Attach Files", systemImage: "plus") { parts.isPickingFiles = true }
                .labelStyle(.iconOnly)
                .buttonStyle(DirectionTextButtonStyle())
                .help("Attach files… (⌘U)")
                .padding(.trailing, DS.Space.xs)
            ForEach(Array(factList.enumerated()), id: \.element.command) { index, fact in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(.dsTextQuaternary)
                }
                Button(fact.title) { openFact = fact.command }
                    .buttonStyle(DirectionTextButtonStyle(rest: .dsTextSecondary))
                    .help("Change \(fact.command.rawValue)")
            }
        }
        .lineLimit(1)
    }

    private var factList: [QuietFact] {
        var facts: [QuietFact] = []
        if let model = parts.modelName { facts.append(QuietFact(command: .model, title: model)) }
        if let effort = parts.effortName { facts.append(QuietFact(command: .effort, title: "\(effort) effort")) }
        if let autonomy = parts.autonomyName { facts.append(QuietFact(command: .autonomy, title: autonomy)) }
        let mode = parts.mode.current
        if mode.id != .build { facts.append(QuietFact(command: .mode, title: mode.name)) }
        return facts
    }

    @ViewBuilder private var trailing: some View {
        if parts.approval != nil {
            Text("⌘Y Allow  ·  ⌘⇧⌫ Reject")
                .lineLimit(1)
        } else if parts.session.canCancel {
            if let hint = parts.followUpHint {
                Text(hint.text)
                    .lineLimit(1)
                    .help(hint.help)
            }
            if parts.hasContent {
                DirectionRoundButton(kind: parts.sendKind, isEnabled: parts.sendBlockedReason == nil) {
                    parts.submit(parts.followUp)
                }
            }
            DirectionRoundButton(kind: .stop, action: parts.stop)
        } else {
            HStack(spacing: DS.Space.sm) {
                MCPComposerChip(session: parts.session, showsCount: true)
                ContextIndicator(session: parts.session, style: .ring)
            }
            if parts.hasContent {
                DirectionRoundButton(kind: parts.sendKind, isEnabled: parts.sendBlockedReason == nil) {
                    parts.submit(parts.followUp)
                }
                .transition(.opacity)
            }
        }
    }
}

/// One setting in the facts line, named by its value.
private struct QuietFact {
    let command: CommandLineSettingQuery.Command
    let title: String
}

/// A setting's values in place of the facts line: its name, then each value; the current one is
/// filled. Picking one sets it and closes the row, and so does Done.
private struct QuietChooser: View {
    let parts: ComposerDirectionParts
    let command: CommandLineSettingQuery.Command
    let onClose: () -> Void

    var body: some View {
        let choices = CommandLineSettingQuery.all(
            command, settings: parts.settings, mode: parts.mode, resumedAutonomy: parts.resumedAutonomy)
        HStack(spacing: DS.Space.xs) {
            Text(command.rawValue.capitalized)
                .foregroundStyle(.dsTextTertiary)
                .padding(.trailing, DS.Space.sm)
            ScrollView(.horizontal) {
                HStack(spacing: DS.Space.xxs) {
                    ForEach(choices) { choice in
                        Button(choice.name.directionShortName) {
                            parts.applyChoice(choice)
                            onClose()
                        }
                        .buttonStyle(DirectionChoiceStyle(isCurrent: choice.isCurrent))
                        .help(choice.detail ?? choice.name)
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: DS.Space.md)
            Button("Done", action: onClose)
                .buttonStyle(DirectionTextButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .transition(.opacity)
    }
}

/// Follow-ups waiting for the turn to end, as quiet lines over the text: the first goes next.
private struct QuietQueue: View {
    let parts: ComposerDirectionParts

    var body: some View {
        let prompts = parts.session.queuedPrompts
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                    HStack(spacing: DS.Space.sm) {
                        Text(index == 0 ? "Next" : "Then")
                            .foregroundStyle(.dsTextTertiary)
                            .frame(width: DS.Space.xxxl, alignment: .leading)
                        Text(prompt.text)
                            .foregroundStyle(.dsTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                }
            }
            .font(.dsBody)
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.md)
            .transition(.opacity)
        }
    }
}
#endif
