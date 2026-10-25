#if DEBUG
import ACP
import SwiftUI
import TaskList

enum AllInViewPreviewFixtures {
    static var factsInsights: SidebarTaskInsights {
        SidebarTaskInsights(branch: { summary in
            switch summary.id.id.rawValue {
            case "native-2": "fix/diff-word-wrap"
            case "native-0": "feature/queue-follow-ups-and-preserve-the-current-turn"
            default: nil
            }
        })
    }

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
        let project = app.projects.add(URL(filePath: "/Users/preview/Developer/new-project"))
        app.catalog.replace(AgentDefinition.ID(rawValue: "codex"), in: project.id, with: []) { _ in false }
        return app
    }
}

struct AllInViewPreviewList: View {
    let app: AppModel
    var insights = SidebarTaskInsights()
    @State var filter = TaskFilter()
    @State private var folding = SidebarDayFolding()
    @State private var selection = SidebarSelectionModel()

    var body: some View {
        ScrollView {
            ProjectList(
                listing: SidebarListing(model: app, filter: filter, insights: insights, folding: folding),
                taskAccessory: { _ in EmptyView() }, filter: $filter, selection: selection, select: { _ in },
                folding: folding)
        }
        .environment(\.sidebarAllInView, true)
        .environment(\.sidebarTaskInsights, insights)
        .environment(\.sidebarSelection, selection)
        .sidebarPreviewEnvironment(app)
        .frame(width: DS.Size.sidebarWidth, height: DS.Size.sidebarWidth * 3)
    }
}

#Preview("All in view - Active, unread, failed, pinned and archived") {
    DSPreviewPair { AllInViewPreviewList(app: AllInViewPreviewFixtures.manyTasks()) }
}

#Preview("All in view - Day folding") {
    DSPreviewPair { AllInViewPreviewList(app: SidebarDesignFixture.makeApp("fold")) }
}

#Preview("All in view - Optional facts") {
    DSPreviewPair {
        AllInViewPreviewList(
            app: SidebarDesignFixture.makeApp("facts"), insights: AllInViewPreviewFixtures.factsInsights)
    }
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
