#if NATIVE_AGENT_PICKER_WIP
import SwiftUI

/// One agent in the picker: its icon and name, its state on the right, and under the name why it
/// can't start a session and what to do. One that can't is dimmed and isn't a button; its fix
/// (Check Again, Restart) sits where the state is, so the pointer and touch reach it too.
struct AgentPickerRow: View {
    let option: AgentPickerOption
    let isHighlighted: Bool
    /// The name's matched letters, as character offsets, set at full strength.
    let highlights: [Range<Int>]
    /// The shortcut that starts a session with the default agent (⌘N), shown on its row as on its
    /// card on Home.
    let defaultShortcut: String?
    let onChoose: () -> Void
    /// Runs the agent's fix, returning once the agent has started again or failed to.
    let onRemedy: () async -> Void

    @State private var isFixing = false

    private var isChoosable: Bool {
        option.choice != nil
    }

    var body: some View {
        Group {
            if isChoosable {
                Button(action: onChoose) {
                    content
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(
                    option.choice == .signInThenStart ? "Signs in, then starts a session" : "Starts a session"
                )
                .accessibilityAddTraits(isHighlighted ? .isSelected : [])
            } else {
                content
                    .accessibilityElement(children: .contain)
            }
        }
        .help(help)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.md) {
                AgentIcon(agent: option.agent)
                    .foregroundStyle(iconStyle)
                Text(title)
                    .font(.dsCallout)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.md)
                status
                trailing
            }
            .frame(minHeight: DS.Size.controlXS)
            if let reason = option.reason {
                Text(DSInlineCode.attributed(reason, codeFont: .dsMonoCaption))
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    // Under the name, past the icon.
                    .padding(.leading, DS.Size.rowLeading + DS.Space.md)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.xs)
        .frame(minHeight: max(DS.Size.controlMD, DS.Size.minimumHitTarget))
        .background(
            isHighlighted && isChoosable ? Color.dsSelected : .clear,
            in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
    }

    private var status: some View {
        HStack(spacing: DS.Space.xs) {
            if option.status.isInProgress {
                DotGridLoader(pattern: .settingUp)
                    .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            }
            Text(option.status.label)
        }
        .font(.dsCaption)
        .foregroundStyle(option.status.needsUser ? .dsAttention : .dsTextTertiary)
        .fixedSize()
    }

    @ViewBuilder private var trailing: some View {
        if !isChoosable, let remedy = option.remedy {
            if isFixing {
                DotGridLoader(pattern: .settingUp)
                    .frame(width: DS.Size.statusGlyph, height: DS.Size.controlXS)
                    .foregroundStyle(.dsTextTertiary)
                    .accessibilityLabel("\(remedy.progressTitle) \(option.name)")
            } else {
                Button(remedy.title) {
                    isFixing = true
                    Task {
                        await onRemedy()
                        isFixing = false
                    }
                }
                .buttonStyle(.ds(.secondary))
                .dsHitTarget(DS.Size.controlXS)
                .accessibilityLabel(remedy.accessibilityTitle(for: option.name))
            }
        } else if option.isDefault, isChoosable, let defaultShortcut {
            Kbd(defaultShortcut)
        }
    }

    /// The glyph in the text's color: brighter on the highlighted row, as in the command palette.
    private var iconStyle: Color {
        guard isChoosable else { return .dsTextTertiary }
        return isHighlighted ? .dsTextPrimary : .dsTextSecondary
    }

    /// The name, its matched letters at full strength and the rest dimmed, so it's clear why it
    /// matched.
    private var title: AttributedString {
        var text = AttributedString(option.name)
        guard isChoosable else {
            text.foregroundColor = .dsTextTertiary
            return text
        }
        guard !highlights.isEmpty else {
            text.foregroundColor = .dsTextPrimary
            return text
        }
        text.foregroundColor = .dsTextSecondary
        let characters = Array(text.characters.indices)
        for range in highlights where range.lowerBound < characters.count {
            let end = range.upperBound < characters.count ? characters[range.upperBound] : text.endIndex
            text[characters[range.lowerBound]..<end].foregroundColor = .dsTextPrimary
        }
        return text
    }

    private var accessibilityValue: String {
        [option.status.label, option.reason].compactMap(\.self).joined(separator: ". ")
    }

    /// The whole reason, which the row cuts at two lines.
    private var help: String {
        [option.name, option.status.label, option.reason].compactMap(\.self).joined(separator: " · ")
    }
}
#endif
