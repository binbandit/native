#if DEBUG
import ACP
import Modes
import SwiftUI

/// Direction B: a command line. A prompt mark says what Return does (send, steer, or answer), `/`
/// and `@` open their lists inside the composer rather than over the conversation, and every
/// setting is a command (`/model`, `/effort`, `/autonomy`, `/mode`) whose values list as you type.
/// The status line under the prompt shows the settings in the same words; clicking one writes its
/// command, so the pointer teaches the keys. An approval becomes a one-line prompt answered by keys.
struct CommandLineComposer<Editor: View, Sections: View, Files: View>: View {
    let parts: ComposerDirectionParts
    @ViewBuilder let editor: (String?) -> Editor
    @ViewBuilder let sections: () -> Sections
    @ViewBuilder let files: () -> Files

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: sections()) { subviews in
                ForEach(subviews) { subview in
                    subview
                    DirectionRule()
                }
            }
            if let list {
                list
                DirectionRule()
            }
            if let approval = parts.approval {
                CommandLineApprovalPrompt(parts: parts, call: approval)
                DirectionRule()
            }
            CommandLineQueue(parts: parts)
            files()
            HStack(alignment: .top, spacing: 0) {
                Text(promptMark)
                    .font(.ds(13, design: .mono))
                    .foregroundStyle(
                        parts.approval != nil ? Color.dsAttention : parts.isWorking ? .dsTextSecondary : .dsAccentText
                    )
                    .frame(minWidth: DS.Space.xl, alignment: .leading)
                    .padding(.leading, DS.Space.lg)
                    .padding(.top, DS.Composer.textInsets.top)
                editor(placeholder)
            }
            DirectionRule()
            CommandLineStatus(parts: parts)
        }
        // A well, like code: the one composer that isn't glass, so it reads as a place to type commands.
        .background(.dsSurfaceSunken, in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(parts.isDropTargeted ? Color.dsAccent : .dsBorder, lineWidth: 1)
        }
        .containerShape(shape)
    }

    /// What Return does, as the prompt's mark.
    private var promptMark: String {
        if parts.approval != nil { return "?" }
        guard parts.session.canCancel else { return "›" }
        return parts.followUp == .steer && parts.session.supportsSteering ? "steer ›" : "queue ›"
    }

    private var placeholder: String {
        let agent = parts.agentName
        if parts.approval != nil {
            return "\(agent) is waiting: answer above, or type to tell it what to do instead"
        }
        if parts.session.canCancel {
            return parts.followUp == .steer && parts.session.supportsSteering
                ? "Add to \(agent)’s turn" : "Queue a follow-up for \(agent)"
        }
        return "Ask \(agent)      / commands and settings   @ files"
    }

    /// The list for what's being typed, inside the composer: a setting's values, commands, or files.
    private var list: CommandLineList? {
        if let query = CommandLineSettingQuery(draft: parts.session.draft) {
            let choices = query.choices(
                settings: parts.settings, mode: parts.mode, resumedAutonomy: parts.resumedAutonomy)
            return choices.isEmpty ? nil : CommandLineList(parts: parts, content: .choices(query.command, choices))
        }
        return parts.suggestions.map { CommandLineList(parts: parts, content: .suggestions($0)) }
    }
}

/// The settings and the context in the prompt's own words, under it: each writes its command when
/// clicked. While the agent works, what it's doing and the keys that steer, queue and stop it.
private struct CommandLineStatus: View {
    let parts: ComposerDirectionParts

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            if parts.session.canCancel {
                let activity = ComposerTurnActivity(session: parts.session)
                HStack(spacing: DS.Space.sm) {
                    DotGridLoader(pattern: .typing)
                        .frame(width: DS.Space.lg, height: DS.Space.lg)
                    Text(parts.agentName.lowercased())
                        .foregroundStyle(.dsTextSecondary)
                    Text(activity.line)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let start = activity.startedAt {
                        ElapsedTimeText(since: start)
                    }
                }
                Spacer(minLength: DS.Space.lg)
                keys([("⌘↩", parts.followUp.opposite.title.lowercased()), ("esc", "stop")])
                Button("Stop", action: parts.stop)
                    .buttonStyle(DirectionTextButtonStyle(rest: .dsTextSecondary))
            } else {
                HStack(spacing: DS.Space.md) {
                    setting("model", parts.modelName)
                    setting("effort", parts.effortName)
                    setting("autonomy", parts.autonomyName)
                    setting("mode", parts.mode.current.name)
                }
                Spacer(minLength: DS.Space.lg)
                HStack(spacing: DS.Space.sm) {
                    MCPComposerChip(session: parts.session, showsCount: true)
                    ContextIndicator(session: parts.session, style: .ring)
                }
                if parts.hasContent {
                    keys([("↩", "send")])
                }
            }
        }
        .font(.dsMonoCaption)
        .foregroundStyle(.dsTextTertiary)
        .lineLimit(1)
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlSM)
    }

    @ViewBuilder
    private func setting(_ command: String, _ value: String?) -> some View {
        if let value {
            Button {
                parts.write("/\(command) ")
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Text(command)
                    Text(value.directionShortName.lowercased())
                        .foregroundStyle(.dsTextSecondary)
                }
            }
            .buttonStyle(DirectionTextButtonStyle())
            .help("Type /\(command) to change it")
        }
    }

    private func keys(_ pairs: [(key: String, action: String)]) -> some View {
        HStack(spacing: DS.Space.md) {
            ForEach(pairs, id: \.key) { pair in
                HStack(spacing: DS.Space.xs) {
                    Text(pair.key)
                        .foregroundStyle(.dsTextSecondary)
                    Text(pair.action)
                }
            }
        }
    }
}

/// The approval as a prompt line: what the agent wants to do, and the keys that answer it. The
/// pointer and touch get the same answers as buttons.
private struct CommandLineApprovalPrompt: View {
    let parts: ComposerDirectionParts
    let call: ToolCallState

    var body: some View {
        let summary = ComposerApprovalSummary(call)
        HStack(spacing: DS.Space.md) {
            DirectionAttentionDot()
            Text("\(parts.agentName.lowercased()) wants to")
                .foregroundStyle(.dsTextTertiary)
            Text(summary.command ?? "\(summary.verb.lowercased()) \(summary.subject)")
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Space.lg)
            ForEach(call.permission?.options ?? []) { option in
                if let key = Self.key(for: option.kind) {
                    Button {
                        parts.answer(option, for: call)
                    } label: {
                        HStack(spacing: DS.Space.xs) {
                            Kbd(key)
                            Text(Self.word(for: option.kind))
                        }
                    }
                    .buttonStyle(DirectionTextButtonStyle(rest: .dsTextSecondary))
                    .help(option.name)
                }
            }
        }
        .font(.dsMonoCaption)
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlMD)
    }

    private static func key(for kind: PermissionOption.Kind) -> String? {
        switch kind {
        case .allowOnce: "⌘Y"
        case .allowAlways: "⌥⌘Y"
        case .rejectOnce: "⌘⇧⌫"
        case .rejectAlways: nil
        }
    }

    private static func word(for kind: PermissionOption.Kind) -> String {
        switch kind {
        case .allowOnce: "allow"
        case .allowAlways: "always"
        case .rejectOnce, .rejectAlways: "reject"
        }
    }
}

/// Queued follow-ups as numbered lines, like a shell's job list: the first goes next.
private struct CommandLineQueue: View {
    let parts: ComposerDirectionParts

    var body: some View {
        let prompts = parts.session.queuedPrompts
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                    HStack(spacing: DS.Space.md) {
                        Text("queued \(index + 1)")
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextTertiary)
                        Text(prompt.text)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                            .lineLimit(1)
                            .onTapGesture { parts.edit(prompt) }
                        Spacer(minLength: DS.Space.md)
                        Button("↑ edit") { parts.edit(prompt) }
                            .buttonStyle(DirectionTextButtonStyle())
                        Button("× remove") { parts.remove(prompt.id) }
                            .buttonStyle(DirectionTextButtonStyle())
                    }
                    .font(.dsMonoCaption)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
            .transition(.opacity)
            DirectionRule()
        }
    }
}
#endif
