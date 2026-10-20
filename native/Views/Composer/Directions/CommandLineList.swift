#if DEBUG
import ACP
import SwiftUI

/// Direction B's list, inside the composer above the prompt: a setting's values while its command is
/// typed, the commands while a bare `/name` is, files for an `@` mention. Settings come first among
/// the commands, each with its current value, then Native's own, then the agent's.
struct CommandLineList: View {
    enum Content {
        case choices(CommandLineSettingQuery.Command, [CommandLineChoice])
        case suggestions(ComposerSuggestions)
    }

    let parts: ComposerDirectionParts
    let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    rows
                }
                .padding(.vertical, DS.Space.sm)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: Self.maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: parts.highlighted) { _, index in
                proxy.scrollTo(index)
            }
        }
        .transition(.opacity)
    }

    private static let maxHeight: CGFloat = DS.Size.listRow * 9

    @ViewBuilder private var rows: some View {
        switch content {
        case .choices(let command, let choices):
            header("/\(command.rawValue)")
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                row(index) {
                    parts.write("")
                    parts.applyChoice(choice)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.dsMicro)
                        .foregroundStyle(.dsTextSecondary)
                        .opacity(choice.isCurrent ? 1 : 0)
                        .frame(width: DS.Space.lg)
                    Text(choice.name.directionShortName)
                        .font(.dsMono)
                        .foregroundStyle(.dsTextPrimary)
                    if let detail = choice.detail {
                        Text(detail)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                    }
                }
            }
        case .suggestions(.commands(let commands)):
            let settings = commands.filter { $0.isNative && CommandLineSettingQuery.Command(rawValue: $0.name) != nil }
            let others = commands.filter { !settings.contains($0) }
            let ordered = settings + others
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, command in
                if index == 0, !settings.isEmpty {
                    header("settings")
                }
                if index == settings.count {
                    header(command.isNative ? "native" : parts.agentName.lowercased())
                } else if index > settings.count, !command.isNative, ordered[index - 1].isNative {
                    header(parts.agentName.lowercased())
                }
                row(index) {
                    parts.chooseCommand(command)
                } label: {
                    Text("/\(command.name)")
                        .font(.dsMono)
                        .foregroundStyle(.dsTextPrimary)
                        .frame(minWidth: DS.Size.popoverWidth / 4, alignment: .leading)
                    Text(command.description)
                        .font(.dsBody)
                        .foregroundStyle(index < settings.count ? .dsTextSecondary : .dsTextTertiary)
                        .lineLimit(1)
                }
            }
        case .suggestions(.files(let files, let query)):
            header("@ files")
            ForEach(Array(files.enumerated()), id: \.element) { index, path in
                row(index) {
                    parts.chooseFile(path, query)
                } label: {
                    Image(systemName: FileMention.isFolder(path) ? "folder" : "doc")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .frame(width: DS.Space.lg)
                    Text(path)
                        .font(.dsMono)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    if parts.changedFiles.contains(path) {
                        Text("changed")
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoCaption)
            .foregroundStyle(.dsTextTertiary)
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.sm)
            .padding(.bottom, DS.Space.xxs)
    }

    private func row(_ index: Int, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        let isHighlighted = index == parts.highlighted
        return Button(action: action) {
            HStack(spacing: DS.Space.md) {
                label()
                Spacer(minLength: 0)
                if isHighlighted {
                    Text("↩")
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.Size.listRow)
            .background(isHighlighted ? Color.dsSelected : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(index)
    }
}
#endif
