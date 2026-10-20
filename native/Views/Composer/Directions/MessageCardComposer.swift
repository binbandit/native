#if DEBUG
import ACP
import Modes
import SwiftUI

/// Direction C: the draft is the next message. It's written in the message's own shape, and its
/// settings ride on it as chips (model, effort, autonomy, mode) that change this message and the
/// ones after it. Sent, the message keeps its chips in the transcript, so every turn says what it
/// ran with. Queued follow-ups wait above it as messages not yet sent.
struct MessageCardComposer<Editor: View, Sections: View, Files: View>: View {
    let parts: ComposerDirectionParts
    @ViewBuilder let editor: (String?) -> Editor
    @ViewBuilder let sections: () -> Sections
    @ViewBuilder let files: () -> Files

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TranscriptMetrics.promptBubbleRadius, style: .continuous)
        VStack(alignment: .trailing, spacing: DS.Space.md) {
            MessageCardQueue(parts: parts)
            status
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: sections()) { subviews in
                    ForEach(subviews) { subview in
                        subview
                        DirectionRule()
                    }
                }
                files()
                editor(nil)
                    .padding(.horizontal, DS.Space.xs)
                    .padding(.top, DS.Space.xs)
                chipsRow
            }
            .dsGlassEffect(in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(parts.isDropTargeted ? Color.dsAccent : .dsBorder, lineWidth: 1)
            }
            .containerShape(shape)
        }
        .onChange(of: lastUserMessage) { _, text in
            if let text {
                MessageSettingsLedger.shared.record(text, facts: currentFacts)
            }
        }
    }

    /// What the agent is doing or waiting for, in a line over the message being written.
    @ViewBuilder private var status: some View {
        if parts.approval != nil {
            HStack(spacing: DS.Space.sm) {
                DirectionAttentionDot()
                Text("\(parts.agentName) is waiting for your approval above")
            }
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.lg)
        } else if parts.session.canCancel {
            let activity = ComposerTurnActivity(session: parts.session)
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .typing)
                    .frame(width: DS.Space.lg, height: DS.Space.lg)
                Text("\(parts.agentName) · \(activity.line)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let start = activity.startedAt {
                    ElapsedTimeText(since: start)
                        .monospacedDigit()
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.lg)
        }
    }

    /// The message's settings as chips, then Send (or Stop while the agent works).
    private var chipsRow: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(chips, id: \.command) { chip in
                MessageCardChip(parts: parts, command: chip.command, title: chip.title)
            }
            Button("Attach Files", systemImage: "paperclip") { parts.isPickingFiles = true }
                .labelStyle(.iconOnly)
                .buttonStyle(DirectionTextButtonStyle())
                .padding(.leading, DS.Space.xs)
                .help("Attach files… (⌘U)")
            Spacer(minLength: DS.Space.md)
            ContextIndicator(session: parts.session, style: .ring)
            if parts.session.canCancel {
                if parts.hasContent {
                    DirectionRoundButton(kind: parts.sendKind, isEnabled: parts.sendBlockedReason == nil) {
                        parts.submit(parts.followUp)
                    }
                }
                DirectionRoundButton(kind: .stop, action: parts.stop)
            } else {
                DirectionRoundButton(
                    kind: parts.sendKind, isEnabled: parts.hasContent && parts.sendBlockedReason == nil
                ) {
                    parts.submit(parts.followUp)
                }
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.bottom, DS.Space.md)
        .padding(.top, DS.Space.xxs)
    }

    private var chips: [(command: CommandLineSettingQuery.Command, title: String)] {
        var chips: [(command: CommandLineSettingQuery.Command, title: String)] = []
        if let model = parts.modelName { chips.append((command: .model, title: model)) }
        if let effort = parts.effortName { chips.append((command: .effort, title: effort)) }
        if let autonomy = parts.autonomyName { chips.append((command: .autonomy, title: autonomy)) }
        chips.append((command: .mode, title: parts.mode.current.name))
        return chips
    }

    private var currentFacts: [String] {
        chips.map(\.title)
    }

    /// The newest message the user sent, which takes the settings it went out with.
    private var lastUserMessage: String? {
        for item in parts.session.state.items.reversed() {
            if case .message(let message) = item, message.role == .user {
                return message.text
            }
        }
        return nil
    }
}

/// One of the message's settings: its value in a capsule, opening the values to pick from.
private struct MessageCardChip: View {
    let parts: ComposerDirectionParts
    let command: CommandLineSettingQuery.Command
    let title: String

    @State private var isHovered = false

    var body: some View {
        let choices = CommandLineSettingQuery.all(
            command, settings: parts.settings, mode: parts.mode, resumedAutonomy: parts.resumedAutonomy)
        Menu {
            Section(command.rawValue.capitalized) {
                ForEach(choices) { choice in
                    Toggle(isOn: Binding(get: { choice.isCurrent }, set: { _ in parts.applyChoice(choice) })) {
                        Text(choice.name)
                        if let detail = choice.detail { Text(detail) }
                    }
                }
            }
        } label: {
            Text(title.directionShortName)
                .font(.dsBody)
                .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
                .padding(.horizontal, DS.Space.md)
                .frame(height: DS.Size.controlXS)
                .background(isHovered ? Color.dsSelected : .dsHover, in: .capsule)
                .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .trackHover($isHovered)
        .help("This message’s \(command.rawValue). Changes this and the next messages.")
        .accessibilityLabel("\(command.rawValue.capitalized): \(title)")
    }
}

/// Follow-ups waiting for the turn: messages not sent yet, in their shape, dashed.
private struct MessageCardQueue: View {
    let parts: ComposerDirectionParts

    var body: some View {
        let prompts = parts.session.queuedPrompts
        if !prompts.isEmpty {
            VStack(alignment: .trailing, spacing: DS.Space.md) {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                    VStack(alignment: .trailing, spacing: DS.Space.xs) {
                        let bubble = RoundedRectangle(
                            cornerRadius: TranscriptMetrics.promptBubbleRadius, style: .continuous)
                        Text(prompt.text)
                            .font(.dsCallout)
                            .foregroundStyle(.dsTextSecondary)
                            .lineLimit(3)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.vertical, DS.Space.md)
                            .background(.dsSurface, in: bubble)
                            .overlay {
                                bubble.strokeBorder(.dsBorderHover, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            }
                            .onTapGesture { parts.edit(prompt) }
                        HStack(spacing: DS.Space.md) {
                            Text(index == 0 ? "Queued · sends when this turn ends" : "Queued · after that")
                                .foregroundStyle(.dsTextTertiary)
                            if parts.session.sendNowRoute != nil {
                                Button("Send now") { parts.sendNow(prompt.id) }
                                    .buttonStyle(DirectionTextButtonStyle(rest: .dsTextSecondary))
                            }
                            Button("Remove") { parts.remove(prompt.id) }
                                .buttonStyle(DirectionTextButtonStyle(rest: .dsTextSecondary))
                        }
                        .font(.dsCaption)
                        .padding(.trailing, DS.Space.xs)
                    }
                    .padding(.leading, DS.Size.contentColumn / 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(.opacity)
        }
    }
}

/// The settings a sent message went out with, under its bubble in the transcript.
struct SentMessageSettings: View {
    let facts: [String]

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                Text(fact.directionShortName)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .padding(.horizontal, DS.Space.sm)
                    .frame(height: DS.Size.statusGlyph + DS.Space.xs)
                    .overlay { Capsule().strokeBorder(.dsSeparator, lineWidth: 1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sent with \(facts.joined(separator: ", "))")
    }
}
#endif
