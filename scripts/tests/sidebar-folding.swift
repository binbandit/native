import ACP
import Experiments
import Foundation
import NativeCommands
import TaskList

@testable import Native

@main @MainActor
private struct SidebarFoldingChecks {
    static func main() throws {
        let app = SidebarDesignFixture.makeApp("fold")
        let folding = SidebarDayFolding()
        let project = try require(app.projects.all.first, "fixture project")
        let old = SessionKey(agent: AgentDefinition.ID(rawValue: "codex"), id: SessionID("native-7"))
        func listing(_ filter: TaskFilter = TaskFilter()) -> SidebarListing {
            SidebarListing(model: app, filter: filter, insights: SidebarTaskInsights(), folding: folding)
        }
        let original = app.sessionList.map(\.id)
        check(!listing().order.contains(old), "Read tasks from yesterday fold")
        check(listing().groups.map { $0.earlier.count } == [2, 2, 2], "Each project owns its earlier disclosure")
        check(
            SidebarListing(model: app, filter: TaskFilter(), insights: SidebarTaskInsights()).order == original,
            "Switch off preserves the original order")
        folding.setExpanded(project.id, true)
        check(listing().order.contains(old), "Disclosure reveals earlier tasks")
        let expanded = listing().order
        folding.setExpanded(project.id, false)
        folding.setExpanded(project.id, true)
        check(listing().order == expanded, "Reopening keeps the same order")
        folding.setExpanded(project.id, false)
        app.setUnread(old, true)
        check(listing().order.contains(old), "Unread older work remains visible")
        app.setUnread(old, false)
        app.renaming = old
        check(listing().order.contains(old), "Renaming cannot lose its field")
        folding.setExpanded(project.id, true)
        check(
            listing().groups.first?.earlier.contains { $0.id == old } == true,
            "Renaming an expanded earlier row keeps its position")
        app.renaming = nil
        folding.setExpanded(project.id, false)
        check(listing(TaskFilter(statuses: [.idle])).order.contains(old), "Filters expose old matches")
        app.sidebarPreferences.setFoldAfter(.week)
        check(listing().order.contains(old), "A week keeps yesterday visible")
        app.sidebarPreferences.setFoldAfter(.never)
        check(listing().order == original, "Never restores original ordering")
        app.sidebarPreferences.setFoldAfter(.day)
        app.ordering.pin(old)
        check(listing().pinned.contains { $0.id == old }, "Pinned older tasks stay visible")
        _ = app.ordering.unpin(old)
        app.selection = listing().order.first
        app.selectSession(offset: 1, in: listing().order)
        check(app.selection == listing().order.dropFirst().first, "Arrow navigation follows visible rows")
        let picks = SidebarSelectionModel()
        picks.update(order: listing().order)
        picks.selectAll(listing().order)
        check(!picks.keys.contains(old), "Bulk selection excludes hidden tasks")
        app.experiments.set(true, for: .sidebarNext)
        picks.setArchiveOrder { listing().order }
        app.setArchiveNavigationOrder(picks)
        app.selection = listing().order.first
        let commands = NativeCommand.taskActions(model: app)
        let next = try require(commands.first { $0.id == .sessionNext }, "next command")
        next.perform(CommandContext())
        check(app.selection == listing().order.dropFirst().first, "Next Task skips folded tasks")
        let first = try require(commands.first { $0.id == .sessionSelect(1) }, "numbered command")
        first.perform(CommandContext())
        check(app.selection == listing().order.first, "Numbered shortcuts follow the sidebar")
        check(app.sessionList.map(\.id) == original, "Folding never rewrites saved order")
        try checkHomeIdentity(app)
        print("Sidebar folding checks passed")
    }

    static func checkHomeIdentity(_ app: AppModel) throws {
        let task = try require(app.homeNextTasks(retaining: nil).first { $0.request != nil }, "Home ask")
        let request = try require(task.request, "Home request")
        let session = try require(app.session(task.id), "owning task")
        let attention = try require(
            SidebarSessionAttention(session: session, task: task.id, oldest: nil), "sidebar ask")
        check(request.taskPeekID(task: task.id) == attention.id, "Home and sidebar identify the same ask")
        let child = session.addSubagent(SessionID("fold-child"))
        app.sessions.register(child)
        child.previewPermissionRequest(command: "swift test", at: .distantPast)
        let childCall = try require(child.permissionRequests.first, "child permission")
        let childRequest = HomeNextRequest(session: child, call: childCall)
        let childAttention = try require(
            SidebarSessionAttention(session: session, task: task.id, oldest: nil), "child sidebar ask")
        check(childRequest.taskPeekID(task: task.id) == childAttention.id, "Child request matches at its parent's row")
        check(
            request.taskPeekID(task: task.id) != childAttention.id, "Different asks on one task never fold each other")
        child.state.resolvePermission(toolCallID: childCall.id)
        child.previewPermissionRequest(command: "swift build", at: .distantPast)
        let successor = try require(
            SidebarSessionAttention(session: session, task: task.id, oldest: nil), "successor ask")
        check(
            childRequest.taskPeekID(task: task.id) != successor.id, "A successor ask is never hidden by a stale request"
        )
    }

    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw MissingFixture(message: message) }
        return value
    }

    private struct MissingFixture: Error { let message: String }
}
