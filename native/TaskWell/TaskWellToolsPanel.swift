import SwiftUI

struct TaskWellToolsPanel<Dev: View>: View {
    let content: TaskWellContent
    let location: String
    @Bindable var tools: SessionToolsScreenModel
    let detail: (TaskWellTool) -> String
    @ViewBuilder var dev: () -> Dev

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(content.agent).font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
                Text(location).font(.dsBody).foregroundStyle(.dsTextTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(DS.Space.lg)
            SeparatorLine()
            if tools.showsWellDev {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Button("Back to tools", systemImage: "chevron.left", action: tools.showWellTools)
                        .buttonStyle(.plain)
                    dev()
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
                                    .foregroundStyle(.dsTextSecondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: DS.Space.sm)
                                Text(CommandRegistry.shared.shortcut(for: tool.command)?.displayString ?? "")
                                    .font(.dsMonoMicro)
                                    .foregroundStyle(.dsTextQuaternary)
                            }
                            .font(DS.TaskWell.row)
                            .padding(.horizontal, DS.Space.sm)
                            .frame(minHeight: DS.TaskWell.rowHeight)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .dsHitTarget(DS.TaskWell.rowHeight)
                    }
                }
                .padding(DS.Space.xs)
            }
        }
        .frame(width: DS.TaskWell.panelWidth)
        .dsPopoverBackground()
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
