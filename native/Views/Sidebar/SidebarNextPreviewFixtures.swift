#if DEBUG
import ACP
import SwiftUI
import TaskList

enum SidebarNextPreviewFixtures {
    static func manyTasks() -> AppModel {
        let app = SidebarPreviewFixtures.troubledApp()
        guard let project = app.previewProject() else { return app }
        for index in 0..<7 {
            app.catalog.add(
                SessionInfo(
                    sessionId: SessionID("quiet-resting-\(index)"), cwd: project.path,
                    title: index == 0
                        ? "Keep a very long task title readable in a narrow sidebar" : "Resting task \(index)",
                    updatedAt: Date.now.addingTimeInterval(-Double(index + 1) * 3600)),
                for: AgentDefinition.ID(rawValue: "codex"), in: project.id)
        }
        return app
    }

    static func emptyProject() -> AppModel {
        let app = AppModel.preview(.empty)
        _ = app.projects.add(URL(filePath: "/Users/preview/Developer/new-project"))
        return app
    }
}

private struct SidebarNextPreviewList: View {
    let app: AppModel
    @State var filter = TaskFilter()
    @State private var selection = SidebarSelectionModel()

    var body: some View {
        ScrollView {
            ProjectList(
                listing: SidebarListing(model: app, filter: filter, insights: SidebarTaskInsights()),
                taskAccessory: { _ in EmptyView() }, filter: $filter, selection: selection, select: { _ in })
        }
        .environment(\.sidebarQuietProjects, true)
        .environment(\.sidebarSelection, selection)
        .sidebarPreviewEnvironment(app)
        .frame(width: DS.Size.sidebarWidth, height: DS.Size.sidebarWidth * 3)
    }
}

#Preview("Quiet projects - Folded, active, unread, failed, pinned and archived") {
    DSPreviewPair { SidebarNextPreviewList(app: SidebarNextPreviewFixtures.manyTasks()) }
}

#Preview("Quiet projects - No projects") {
    DSPreviewPair { SidebarNextPreviewList(app: AppModel.preview(.empty)) }
}

#Preview("Quiet projects - First task") {
    DSPreviewPair { SidebarNextPreviewList(app: SidebarNextPreviewFixtures.emptyProject()) }
}

#Preview("Quiet projects - Starting and listing failure") {
    DSPreviewPair { SidebarNextPreviewList(app: SidebarPreviewFixtures.troubledApp()) }
}

#Preview("Quiet projects - Filter with no matches") {
    DSPreviewPair {
        SidebarNextPreviewList(
            app: AppModel.preview(), filter: TaskFilter(statuses: [.failed], agents: ["claude-code"]))
    }
}
#endif
