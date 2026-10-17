import ACP
import SwiftUI

/// The slash commands matching the draft, floating above the composer like Factory's suggestion
/// list. The editor keeps focus and drives the highlight with the arrow keys; Return or Tab inserts
/// the highlighted command.
struct SlashCommandList: View {
    let commands: [ComposerSlashCommand]
    @Binding var highlighted: Int
    let onChoose: (ComposerSlashCommand) -> Void

    var body: some View {
        ComposerSurface(isFloating: true) {
            ScrollViewReader { proxy in
                CappedHeightScrollView(maxHeight: ComposerMetrics.suggestionListMaxHeight) {
                    VStack(spacing: 0) {
                        ForEach(commands.indices, id: \.self) { index in
                            row(commands[index], at: index)
                                .id(index)
                        }
                    }
                    .padding(DS.Space.xs)
                }
                .onChange(of: highlighted) {
                    proxy.scrollTo(highlighted)
                }
            }
        }
    }

    private func row(_ command: ComposerSlashCommand, at index: Int) -> some View {
        let isHighlighted = index == highlighted
        return Button {
            onChoose(command)
        } label: {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "command")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.rowLeading)
                Text(verbatim: "/\(command.name)")
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
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.Size.listRow)
            .background(isHighlighted ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { highlighted = index }
        }
        .help(command.description)
        .accessibilityLabel("/\(command.name): \(command.description)")
    }
}
