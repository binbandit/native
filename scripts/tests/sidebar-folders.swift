import Experiments
import Foundation
import NativePolicy
import SwiftUI
import TaskList

@testable import Native

@main
@MainActor
private struct SidebarFolderChecks {
    static func main() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "native-folder-check-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let atlas = scratch.appending(path: "atlas", directoryHint: .isDirectory)
        let pier = scratch.appending(path: "pier", directoryHint: .isDirectory)
        let alias = scratch.appending(path: "alias", directoryHint: .isDirectory)
        let file = scratch.appending(path: "notes.txt")
        let package = scratch.appending(path: "Fixture.app", directoryHint: .isDirectory)
        for folder in [atlas, pier, package] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: atlas)
        try Data("fixture".utf8).write(to: file)

        let approved = scratch.appending(path: "approved", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: approved, withIntermediateDirectories: true)
        let escape = approved.appending(path: "outside")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: pier)
        let limited = PolicyLoader.load(
            from: StaticPolicySource(managed: ["policy.folders.allowedRoots": [approved.path]]))
        let escaped = await PlatformFolderAccess.inspect([escape], policy: limited)
        require(escaped.first?.failure != nil, "a symlink cannot escape an approved root")

        let app = AppModel.preview()
        app.sidebarFolders.policyOverride = .default
        let previous = app.projects.all
        guard let session = SessionModel.preview(in: app) else { fatalError("missing session fixture") }
        session.draft = "Keep this draft"
        app.selection = session.key
        let count = app.sessionList.count
        let resolved = await PlatformFolderAccess.inspect([atlas, alias, pier, file, package], policy: .default)
        app.sidebarFolders.dismissResult()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let added = app.finishOpeningFolders(resolved, undoManager: undo)
        undo.endUndoGrouping()
        require(added.count == 2, "aliases deduplicate and files/packages are rejected")
        require(app.projects.all.count == previous.count + 2, "the batch adds exactly two projects")
        require(app.currentProject?.id == added.first?.id, "the first newly added folder opens its home")
        require(
            app.sidebarFolders.failures.count == 2,
            "rejected names remain in the result: \(app.sidebarFolders.failures.count) \(app.sidebarFolders.failures.map(\.message))"
        )
        require(app.sidebarFolders.history.entries.count == 2, "only successful canonical folders enter recents")
        require(session.draft == "Keep this draft", "opening preserves the old task draft")
        require(app.sessionList.count == count, "opening creates no task")
        undo.undo()
        require(app.projects.all == previous, "one undo removes only the new batch")
        require(app.selection == session.key, "undo restores the task behind the addition")
        require(session.draft == "Keep this draft", "undo preserves the draft")
        require(app.sidebarFolders.receipt == nil, "keyboard undo clears the receipt")

        let first = app.finishOpeningFolders(
            await PlatformFolderAccess.inspect([atlas], policy: .default), undoManager: nil)
        app.dismissFolderResult()
        let again = app.finishOpeningFolders(
            await PlatformFolderAccess.inspect([alias], policy: .default), undoManager: nil)
        require(first.count == 1 && again.isEmpty, "an already-open symlink alias is a no-op")
        require(app.sidebarFolders.receipt == nil, "a no-op never offers an addition undo")
        let total = app.projects.all.count
        app.clearRecentFolders()
        require(app.projects.all.count == total, "clearing recents never closes projects")
        require(app.sidebarFolders.history.entries.isEmpty, "clear removes the history")

        let inspected = await PlatformFolderAccess.inspect([pier], policy: .default)
        app.sidebarFolders.policyOverride = PolicyLoader.load(
            from: StaticPolicySource(managed: ["policy.folders.allowedRoots": [String]()]))
        require(app.finishOpeningFolders(inspected, undoManager: nil).isEmpty, "policy is revalidated at commit")
        require(app.projects.all.count == total, "a denied addition leaves projects intact")
        app.sidebarFolders.policyOverride = .default
        app.dismissFolderResult()
        let invalid = FolderHistory.Entry(url: atlas, bookmark: Data([1, 2, 3]))
        await app.openRecentFolder(invalid, undoManager: nil)
        require(
            app.sidebarFolders.failures.first?.reason == "Folder access expired.", "expired bookmarks offer renewal")
        require(app.projects.all.count == total, "a stale recent never removes an existing project")
        let abandoned = app.beginFolderDrop()
        app.endFolderDrop()
        await app.previewFolderDrop([atlas], request: abandoned)
        require(
            !app.sidebarFolders.acceptsDrop && app.sidebarFolders.hovered.isEmpty,
            "an old hover cannot revive after leaving")
        app.experiments.set(true, for: .sidebarNext)
        app.setHomeNextVisible(true)
        app.selection = nil
        require(app.homeNextOwnsNewTask, "the folder home owns Command-N without requiring the Home switch")
        app.setHomeNextVisible(false)
        app.folderPickerFinished(.success(nil), undoManager: nil)
        require(app.projects.all.count == total, "cancelling a chooser keeps the workspace")
        print(
            "PASS: folder batches, symlink identity, files/packages, recents, undo, drafts, cancellation and policy revalidation"
        )
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
