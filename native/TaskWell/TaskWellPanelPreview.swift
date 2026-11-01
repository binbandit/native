#if DEBUG
import SessionTools
import SwiftUI

struct TaskWellPanelPreview: View {
    var isManaged = false
    var isRemote = false
    var isEmpty = false
    var hasManyTools = false
    @State private var tools = SessionToolsScreenModel(registry: TaskWellPreviewFixtures.registryWithPluginTool())

    var body: some View {
        TaskWellToolsPanel(
            content: TaskWellPreviewFixtures.states[isEmpty ? 0 : 8],
            identity: TaskWellIdentity(
                model: "6.1 Sol", machine: isRemote ? "On Build Mac" : "On this Mac",
                timing: isEmpty ? nil : "last turn 2m 4s", contextFraction: isEmpty ? nil : 0.41,
                isManaged: isManaged, management: isManaged ? "Managed by Northwind Federal IT · #it-help" : nil,
                project: "native",
                branch: isRemote ? "feature/a-long-branch-name-for-wrapping-the-diff" : "feature/diff"),
            tools: tools, detail: detail
        ) { page in
            Text(page == .dev ? "No project actions yet" : "No subagents on this task")
                .font(.dsBody).foregroundStyle(.dsTextTertiary)
        }
        .onAppear {
            if hasManyTools { tools.registry.setPluginTools(TaskWellFixturePlugin.manyTools) }
            tools.hasWell = true
            tools.wellToolAvailable = {
                if tools.registry.place(for: $0.spec) == .off { return false }
                if isRemote && $0 == .dev { return false }
                return isEmpty ? $0 == .changes || $0 == .terminal || $0 == .dev : true
            }
        }
    }

    private func detail(_ tool: TaskWellTool) -> TaskWellToolDetail {
        switch tool {
        case .changes:
            TaskWellToolDetail(
                text: isEmpty ? "No changes" : "3 files", stats: isEmpty ? nil : .init(added: 44, removed: 6))
        case .terminal:
            TaskWellToolDetail(
                text: isRemote ? "Not available here" : "zsh · native/feature-diff",
                unavailableReason: isRemote
                    ? "This task runs on another machine. Its terminal cannot be opened on this Mac." : nil)
        case .dev:
            TaskWellToolDetail(
                text: isEmpty ? "2 actions to run" : "Dev · running", isSelected: !isEmpty, isRunning: !isEmpty,
                note: isManaged ? "Repository actions are off. Your actions are still available." : nil,
                isManaged: isManaged)
        case .subagents: TaskWellToolDetail(text: "3 workers · 2 working")
        case .pullRequest: TaskWellToolDetail(text: "#128 Open · 3 checks passed")
        default: TaskWellToolDetail(text: "ACME-142 · In review", isRunning: true)
        }
    }
}

#Preview("Well - Empty tools") {
    DSPreviewPair { TaskWellPanelPreview(isEmpty: true) }
}

#Preview("Well - 25 plugin tools") {
    DSPreviewPair { TaskWellPanelPreview(hasManyTools: true) }
}
#endif
