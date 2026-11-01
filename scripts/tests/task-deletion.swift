import ACP
import Foundation
import Undo

@testable import Native

private struct TaskDeletionFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
private struct TaskDeletionRegression {
    static func main() async {
        do {
            try await check()
            print(
                "PASS: delete acts immediately, Undo preserves tasks, expiry withdraws Undo, archive restores workspaces"
            )
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func check() async throws {
        let app = AppModel.preview(.empty)
        let workspaces = TaskDeletionWorkspaces()
        app.taskWorkspaces = workspaces
        let project = app.projects.add(URL(filePath: "/fixture/project", directoryHint: .isDirectory))
        var tasks: [SessionModel] = []
        for index in 1...3 {
            let session = try require(
                SessionModel.preview(
                    in: app, id: "delete-\(index)", cwd: "/fixture/worktree-\(index)", title: "Task \(index)"),
                "No fixture session")
            session.previewExchange("Fixture prompt", reply: "Fixture reply")
            session.draft = "Unsent draft"
            app.catalog.add(
                SessionInfo(sessionId: session.id, cwd: session.cwd.folderPath, title: session.displayTitle),
                for: session.agent.id, in: project.id)
            tasks.append(session)
        }
        let keys = tasks.map(\.key)
        let selected = SidebarSelectionModel()
        selected.update(order: keys)
        selected.selectAll(keys)
        let manager = UndoManager()
        manager.groupsByEvent = false
        let context = CommandContext(sidebarSelection: selected, windowUndoManager: manager)
        let command = try require(
            NativeCommand.sidebarSelection(model: app).first { $0.id == .selectionDelete }, "No Delete command")

        // The menu/palette must take the same immediate path as a row, without a confirmation.
        manager.beginUndoGrouping()
        command.perform(context)
        manager.endUndoGrouping()
        try expect(
            app.pendingDeletionKeys == Set(keys), "Delete Selected Tasks asked for confirmation instead of deleting")
        try expect(selected.keys.isEmpty, "Delete kept its multi-selection")
        try expect(app.sessionList.isEmpty, "Deleted tasks are still visible")
        let bulkUndo = try require(app.offeredUndo, "No bulk Undo")
        try expect(bulkUndo.message == "Deleted 3 tasks.", "Bulk feedback has the wrong count")
        try expect(workspaces.operations.isEmpty, "Delete touched a workspace before Undo expired")
        bulkUndo.undo()
        try expect(app.pendingDeletionKeys.isEmpty, "Bulk Undo left deletions pending")
        try expect(Set(app.sessionList.map(\.id)) == Set(keys), "Bulk Undo did not restore every task")
        for task in tasks {
            try expect(app.sessions.session(task.key) === task, "Undo replaced the loaded transcript/session")
            try expect(task.state.items.count == 2 && task.draft == "Unsent draft", "Undo lost transcript or draft")
        }

        // A pinned, unread task retains its identity, history and flags through Undo and Redo.
        guard let first = tasks.first else { throw TaskDeletionFailure(description: "No first task") }
        app.ordering.pin(first.key)
        app.unread.set(first.key, unread: true)
        manager.beginUndoGrouping()
        app.deleteSession(first.key, undoManager: manager)
        manager.endUndoGrouping()
        try expect(!app.sessionList.contains { $0.id == first.key }, "Pinned deletion stayed visible")
        manager.undo()
        try expect(app.isPinned(first.key) && app.isUnread(first.key), "Undo lost task flags")
        manager.redo()
        try expect(app.pendingDeletionKeys.contains(first.key), "Redo did not restart deletion")
        manager.undo()
        try expect(workspaces.operations.isEmpty, "Undo/Redo ran destructive workspace cleanup")

        // Deleting from Archived also disappears at once; Undo leaves it archived, with its record.
        app.archivedSessions.set(first.key, archived: true)
        let archivedAt = app.archivedSessions.date(first.key)
        app.deleteSession(first.key)
        try expect(app.archivedSessions(in: project.id).isEmpty, "Archived deletion stayed visible during Undo")
        try require(app.offeredUndo, "No archived deletion Undo").undo()
        try expect(
            app.archivedSessions(in: project.id).map(\.id) == [first.key], "Undo did not restore the archived task")
        try expect(app.archivedSessions.date(first.key) == archivedAt, "Undo changed the archive record")

        // Archive and its menu command keep history, restoring each workspace through one Undo.
        app.archivedSessions.set(first.key, archived: false)
        selected.selectAll(keys)
        let archive = try require(
            NativeCommand.taskActions(model: app).first { $0.id == .sessionArchive }, "No Archive command")
        manager.beginUndoGrouping()
        archive.perform(context)
        try await wait { workspaces.operations.filter { $0 == "archive" }.count == keys.count }
        manager.endUndoGrouping()
        try expect(keys.allSatisfy(app.isArchived), "Archive command missed a task")
        try require(app.offeredUndo, "No archive Undo").undo()
        try await wait { workspaces.operations.filter { $0 == "restore" }.count == keys.count }
        try expect(keys.allSatisfy { !app.isArchived($0) }, "Archive Undo left tasks archived")

        await app.archiveSession(first.key)
        try expect(app.isArchived(first.key), "Single archive did not hide the task")
        try require(app.offeredUndo, "No single archive Undo").undo()
        try await wait { workspaces.operations.filter { $0 == "restore" }.count == keys.count + 1 }
        try expect(!app.isArchived(first.key), "Single archive Undo left the task archived")

        // A real grace period elapses: cleanup runs only now, and no stale Undo can restore it.
        workspaces.operations.removeAll()
        manager.removeAllActions()
        manager.beginUndoGrouping()
        app.deleteSessions(keys, undoManager: manager)
        manager.endUndoGrouping()
        let expiring = try require(app.offeredUndo, "No expiring Undo")
        try expect(workspaces.operations.isEmpty, "Cleanup ran before the grace period")
        try await Task.sleep(for: AppModel.deletionGracePeriod + .milliseconds(200))
        try await wait { workspaces.operations.filter { $0 == "deleted" }.count == keys.count }
        try expect(keys.allSatisfy { app.catalog.lookup($0) == nil }, "Expired deletion kept a catalog entry")
        try expect(
            !expiring.canUndo && !manager.canUndo && app.offeredUndo == nil, "Expired deletion still promises Undo")
        expiring.undo()
        try expect(app.sessionList.isEmpty, "Expired Undo resurrected a deleted task")
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TaskDeletionFailure(description: message) }
    }

    static func require<Value>(_ value: Value?, _ message: String) throws -> Value {
        guard let value else { throw TaskDeletionFailure(description: message) }
        return value
    }

    static func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw TaskDeletionFailure(description: "Timed out")
    }
}

/// Records the boundary to git and task scripts; the regression never touches a real workspace.
@MainActor
private final class TaskDeletionWorkspaces: TaskWorkspaceProvider {
    var operations: [String] = []
    func workspaceOptions(in project: Project, current: URL) async throws -> [TaskWorkspaceOption] { [] }
    func workspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> URL { project.url }
    func prepareWorkspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> TaskWorkspacePreparation
    {
        .init(folder: project.url, createdForTask: false)
    }
    func removeUnusedWorkspace(at folder: URL, in project: Project) async throws -> Bool { false }
    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL { project.url }
    func newTaskWorkspaceLabel(in project: Project) -> String { "Fixture" }
    func archiveWorkspace(at folder: URL, in project: Project) async throws -> String? {
        operations.append("archive")
        return "Saved fixture checkpoint."
    }
    func restoreWorkspace(at folder: URL, in project: Project, task: ArchivedTaskDetails?) async throws -> Bool {
        operations.append("restore")
        return true
    }
    func archivedWorkspaceFolders(of project: Project) async -> [URL] { [] }
    func removedWorkspaces(
        among tasks: [(folder: URL, title: String)], in project: Project
    ) async -> [URL: RemovedWorkspace.Fate] {
        [:]
    }
    func restoreRemovedWorkspace(at folder: URL, branch: String, in project: Project) async throws {}
    func deleteWorkspace(at folder: URL, in project: Project) async throws { operations.append("delete") }
    func deleteWorkspaces(of project: Project) async throws {}
    func taskDidGetTitle(_ title: String, request: String?, workspace: URL, in project: Project) async {}
    func taskFolders(of project: Project) async -> [URL] { [] }
    func taskWasDeleted(_ task: SessionKey, title: String, folder: URL, in project: Project) async {
        operations.append("deleted")
    }
}
