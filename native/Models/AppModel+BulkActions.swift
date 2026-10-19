import ACP
import Foundation

// Actions on several tasks at once, from the sidebar's multi-selection. Each acts on the tasks it
// applies to, skips the rest, and offers one undo for the lot.
extension AppModel {
    /// Archives the tasks that aren't archived yet, then puts their workspaces away one at a time
    /// (they may share a repository, whose git locks don't allow two at once). One undo brings them
    /// all back.
    func archiveSessions(_ keys: [SessionKey], undoManager: UndoManager? = nil) async {
        let listed = keys.compactMap { key in
            catalog.lookup(key).flatMap { archivedSessions.contains(key) ? nil : (key, $0.project) }
        }
        guard !listed.isEmpty else { return }
        if listed.count == 1, let (key, _) = listed.first {
            return await archiveSession(key, undoManager: undoManager)
        }
        let titles = Dictionary(listed.map { ($0.0, titleOfSession($0.0)) }) { first, _ in first }
        for (key, project) in listed {
            archivedSessions.set(key, archived: true)
            leave(key, in: project)
        }
        let archived = listed.map(\.0)
        offerUndo("Archived \(listed.count) tasks.", name: "Archive Tasks", undoManager: undoManager) { model in
            Task { await model.unarchiveSessions(archived) }
        }
        for (key, project) in listed where archivedSessions.contains(key) {
            _ = await putAwayWorkspace(of: key, titled: titles[key] ?? "New Session", in: project)
        }
    }

    func unarchiveSessions(_ keys: [SessionKey]) async {
        for key in keys {
            await unarchiveSession(key)
        }
    }

    /// Deletes the tasks after the undo window, like `deleteSession`; one undo keeps them all.
    func deleteSessions(_ keys: [SessionKey], undoManager: UndoManager? = nil) {
        if keys.count == 1, let key = keys.first {
            return deleteSession(key, undoManager: undoManager)
        }
        let scheduled = keys.filter { scheduleDeletion(of: $0) }
        guard !scheduled.isEmpty else { return }
        offerUndo("Deleted \(scheduled.count) tasks.", name: "Delete Tasks", undoManager: undoManager) { model in
            for key in scheduled {
                model.pendingDeletions.removeValue(forKey: key)?.cancel()
            }
        }
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
