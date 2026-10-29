import ACP
import Foundation
import Undo

// Actions on several tasks at once, from the sidebar's multi-selection. Each acts on the tasks it
// applies to, skips the rest, and offers one undo for the lot.
extension AppModel {
    /// Archives the tasks that aren't archived yet, then puts their workspaces away one at a time
    /// (they may share a repository, whose git locks don't allow two at once). One undo brings them
    /// all back, and Redo archives them again.
    func archiveSessions(_ keys: [SessionKey], undoManager: UndoManager? = nil) async {
        let listed = keys.compactMap { key in
            catalog.lookup(key).flatMap { archivedSessions.contains(key) ? nil : (key, $0.project) }
        }
        guard !listed.isEmpty else { return }
        if listed.count == 1, let (key, _) = listed.first {
            return await archiveSession(key, undoManager: undoManager)
        }
        let titles = Dictionary(listed.map { ($0.0, titleOfSession($0.0)) }) { first, _ in first }
        let archived = listed.map(\.0)
        let selected = moveAfterArchiving(archived)
        for (key, _) in listed {
            _ = taskActionRoute(for: key)
            archivedSessions.set(key, archived: true)
        }
        offerUndo("Archived \(listed.count) tasks.", name: "Archive Tasks", undoManager: undoManager) { model in
            model.undoArchive(archived, selecting: selected)
        } redo: { model in
            model.archiveAgain(archived)
        }
        for (key, project) in listed where archivedSessions.contains(key) {
            _ = await putAwayWorkspace(of: key, titled: titles[key] ?? "New Task", in: project)
        }
    }

    func unarchiveSessions(_ keys: [SessionKey]) async {
        let restoring = keys.filter(beginUnarchiving)
        for key in restoring {
            await finishUnarchiving(key)
        }
    }

    /// Archives tasks again for Redo, as archiving them did: off the sidebar at once, then their
    /// workspaces put away one at a time. Their undo is already back on the stack.
    func archiveAgain(_ keys: [SessionKey]) {
        let listed = keys.compactMap { key in
            catalog.lookup(key).flatMap { archivedSessions.contains(key) ? nil : (key, $0.project) }
        }
        moveAfterArchiving(listed.map(\.0))
        for (key, _) in listed {
            _ = taskActionRoute(for: key)
            archivedSessions.set(key, archived: true)
        }
        Task {
            for (key, project) in listed where archivedSessions.contains(key) {
                _ = await putAwayWorkspace(of: key, titled: titleOfSession(key), in: project)
            }
        }
    }

    /// Deletes the tasks after the undo window, like `deleteSession`; one undo keeps them all.
    func deleteSessions(_ keys: [SessionKey], undoManager: UndoManager? = nil, confirmedFolder: Bool = false) {
        if !confirmedFolder, keys.contains(where: { canDelete($0) && usesProjectFolder($0) }) {
            projectFolderDeletion = ProjectFolderDeletion(title: "Delete these tasks?") {
                [weak self, weak undoManager] in
                self?.deleteSessions(keys, undoManager: undoManager, confirmedFolder: true)
            }
            return
        }
        if keys.count == 1, let key = keys.first {
            return deleteSession(key, undoManager: undoManager, confirmedFolder: confirmedFolder)
        }
        let deletable = keys.filter { canDelete($0) }
        guard !deletable.isEmpty else { return }
        let action = UndoableAction("Deleted \(deletable.count) tasks.", name: "Delete Tasks", undoManager: undoManager)
        {
            [weak self] _ in
            for key in deletable {
                self?.cancelDeletion(of: key)
            }
        } redo: { [weak self] action in
            for key in deletable {
                self?.scheduleDeletion(of: key, undo: action)
            }
        }
        for key in deletable {
            scheduleDeletion(of: key, undo: action)
        }
        lastUndoable = action
    }

    func setUnread(_ keys: [SessionKey], _ isUnread: Bool) {
        for key in keys {
            setUnread(key, isUnread)
        }
    }

    /// Pins or unpins the tasks; ⌘Z takes back the whole change.
    func setPinned(_ keys: [SessionKey], _ isPinned: Bool, undoManager: UndoManager? = nil) {
        undoManager?.beginUndoGrouping()
        for key in keys {
            setPinned(key, isPinned, undoManager: undoManager)
        }
        undoManager?.setActionName(isPinned ? "Pin Tasks" : "Unpin Tasks")
        undoManager?.endUndoGrouping()
    }

    /// Stops the turns running in the tasks; the others are left alone.
    func stopSessions(_ keys: [SessionKey]) async {
        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                guard let session = sessions.session(key), session.canCancel else { continue }
                group.addTask { await session.cancel() }
            }
        }
    }

    /// What a bulk action could do for `keys`, so menus only offer what applies.
    func bulkAvailability(of keys: [SessionKey]) -> BulkTaskActions {
        var actions = BulkTaskActions()
        for key in keys {
            if isArchived(key) { actions.canUnarchive = true } else { actions.canArchive = true }
            if isUnread(key) { actions.canMarkRead = true } else { actions.canMarkUnread = true }
            if isPinned(key) { actions.canUnpin = true } else { actions.canPin = true }
            if sessions.session(key)?.canCancel == true { actions.canStop = true }
        }
        return actions
    }
}

/// Which bulk actions apply to a set of tasks: each is available when at least one task would change.
struct BulkTaskActions: Equatable {
    var canArchive = false
    var canUnarchive = false
    var canMarkRead = false
    var canMarkUnread = false
    var canPin = false
    var canUnpin = false
    var canStop = false
}
