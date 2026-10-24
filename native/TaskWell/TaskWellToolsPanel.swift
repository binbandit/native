import ACP
import NativeCommands
import SwiftUI

struct TaskWellToolsPanel<Dev: View>: View {
    let content: TaskWellContent
    let location: String
    @Bindable var tools: SessionToolsScreenModel
    let detail: (TaskWellTool) -> String
    @ViewBuilder var dev: () -> Dev
    @State private var hovered: TaskWellTool?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            SeparatorLine()
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(content.agent).font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
                Text(location).font(.dsBody).foregroundStyle(.dsTextTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.vertical, DS.Space.lg)
            .padding(.horizontal, DS.Space.xl)
            SeparatorLine()
            if tools.showsWellDev {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Button("Back to tools", systemImage: "chevron.left", action: tools.showWellTools)
                        .buttonStyle(.plain)
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Space.sm) { dev() }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: DS.TaskWell.devMaxHeight)
                }
                .padding(DS.Space.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(TaskWellTool.allCases.filter(tools.wellToolAvailable)) { tool in
                        Button {
                            tools.performWellTool(tool)
                        } label: {
                            HStack(spacing: 0) {
                                Image(systemName: tool.symbol)
                                    .foregroundStyle(.dsTextSecondary)
                                    .frame(width: DS.TaskWell.rowIconWidth, alignment: .leading)
                                Text(tool.title)
                                    .foregroundStyle(.dsTextPrimary)
                                    .frame(width: DS.TaskWell.rowTitleWidth, alignment: .leading)
                                Text(detail(tool))
                                    .font(DS.TaskWell.rowDetail)
                                    .foregroundStyle(.dsTextSecondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: DS.Space.sm)
                                Text(CommandRegistry.shared.shortcut(for: tool.command)?.displayString ?? "")
                                    .font(DS.TaskWell.shortcut)
                                    .foregroundStyle(.dsTextQuaternary)
                            }
                            .font(DS.TaskWell.row)
                            .padding(.leading, DS.Space.md)
                            .padding(.trailing, DS.TaskWell.rowTrailing)
                            .frame(minHeight: DS.TaskWell.rowHeight)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .background(hovered == tool ? .dsHover : .clear, in: .rect(cornerRadius: DS.Radius.card))
                        .trackHover(Binding(get: { hovered == tool }, set: { hovered = $0 ? tool : nil }))
                        .dsHitTarget(DS.TaskWell.rowHeight)
                    }
                }
                .padding(DS.Space.sm)
            }
        }
        .frame(width: DS.TaskWell.panelWidth)
        .dsPopoverBackground()
    }

    private var statusHeader: some View {
        HStack(spacing: DS.TaskWell.gap) {
            TaskSignal(
                status: content.status, isUnread: content.status == .done, placement: .well,
                attentionSince: content.attentionSince
            )
            .frame(width: DS.TaskWell.signal, height: DS.TaskWell.signal)
            if let outcome = content.outcome {
                Text("Changed \(outcome.changedFiles.count) \(outcome.changedFiles.count == 1 ? "file" : "files")")
                DiffStatsText(stats: DiffStats(added: outcome.linesAdded, removed: outcome.linesRemoved))
                    .font(DS.TaskWell.object)
            } else {
                Text(content.verb.isEmpty ? content.agent : content.verb)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize()
                if let object = content.object {
                    Text(object).font(DS.TaskWell.object).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: DS.Space.sm)
            Text("esc").font(.dsMonoMicro).foregroundStyle(.dsTextTertiary)
        }
        .font(DS.TaskWell.body)
        .padding(.leading, DS.TaskWell.panelHeaderLeading)
        .padding(.trailing, DS.TaskWell.panelHeaderTrailing)
        .frame(height: DS.TaskWell.panelHeaderHeight)
    }
}

#if DEBUG
#Preview("Well - Tools in key order") {
    let tools = SessionToolsScreenModel()
    tools.wellToolAvailable = { _ in true }
    return DSPreviewPair {
        TaskWellToolsPanel(content: TaskWellPreviewFixtures.states[0], location: "native · feature/diff", tools: tools)
        {
            $0 == .changes ? "3 files" : ""
        } dev: {
            EmptyView()
        }
    }
}
#endif
