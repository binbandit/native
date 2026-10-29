import SwiftUI

/// A slash command in the suggestion list: its name, then what it does.
struct SlashCommandRow: View {
    let command: ComposerSlashCommand
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "command")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.rowLeading)
            Text(verbatim: command.invocation)
                .font(.dsMono)
                .foregroundStyle(isHighlighted ? .dsTextPrimary : .dsTextSecondary)
                .layoutPriority(1)
            Spacer(minLength: DS.Space.xl)
            Text(command.description)
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(command.description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(command.invocation): \(command.description)")
    }
}

#if DEBUG
#Preview("Slash command rows") {
    DSPreviewPair {
        VStack(spacing: DS.Space.sm) {
            ForEach(Array(ComposerPreviewFixtures.commands.enumerated()), id: \.offset) { index, command in
                SlashCommandRow(command: command, isHighlighted: index == 0)
            }
        }
        .frame(width: 420)
    }
}
#endif
