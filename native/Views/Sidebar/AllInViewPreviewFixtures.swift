#if DEBUG
import ACP
import SwiftUI
import TaskList

enum AllInViewPreviewFixtures {
    static func manyTasks() -> AppModel {
        let app = SidebarPreviewFixtures.troubledApp()
        guard let project = app.previewProject() else { return app }
        for index in 0..<7 {
            app.catalog.add(
                SessionInfo(
                    sessionId: SessionID("all-in-view-resting-\(index)"), cwd: project.path,
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

struct AllInViewPreviewList: View {
    let app: AppModel
    @State var filter = TaskFilter()
    @State private var selection = SidebarSelectionModel()

    var body: some View {
        ScrollView {
            ProjectList(
                listing: SidebarListing(model: app, filter: filter, insights: SidebarTaskInsights()),
                taskAccessory: { _ in EmptyView() }, filter: $filter, selection: selection, select: { _ in })
        }
        .environment(\.sidebarAllInView, true)
        .environment(\.sidebarSelection, selection)
        .sidebarPreviewEnvironment(app)
        .frame(width: DS.Size.sidebarWidth, height: DS.Size.sidebarWidth * 3)
    }
}

#Preview("All in view - Active, unread, failed, pinned and archived") {
    DSPreviewPair { AllInViewPreviewList(app: AllInViewPreviewFixtures.manyTasks()) }
}

#Preview("All in view - No projects") {
    DSPreviewPair { AllInViewPreviewList(app: AppModel.preview(.empty)) }
}

#Preview("All in view - First task") {
    DSPreviewPair { AllInViewPreviewList(app: AllInViewPreviewFixtures.emptyProject()) }
}

#Preview("All in view - Starting and listing failure") {
    DSPreviewPair { AllInViewPreviewList(app: SidebarPreviewFixtures.troubledApp()) }
}

#Preview("All in view - Filter with no matches") {
    DSPreviewPair {
        AllInViewPreviewList(
            app: AppModel.preview(), filter: TaskFilter(statuses: [.failed], agents: ["claude-code"]))
    }
}
#endif
