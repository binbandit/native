import ACP
import Foundation
import TaskList
import Undo

// Archiving and deleting tasks and projects. Archive hides and can always come back; delete acts at
// once on screen but waits out the undo window before removing anything for good.
extension AppModel {
    /// How long a deletion can be undone before it's carried out.
    static let deletionGracePeriod: Duration = .seconds(10)

    // MARK: - Tasks

    func isArchived(_ key: SessionKey) -> Bool {
        archivedSessions.contains(key)
    }

    /// A project's archived tasks, most recently archived first, for the Archived view.
    func archivedSessions(in project: Project.ID) -> [SessionSummary] {
        allSessions(in: project)
            .filter { archivedSessions.contains($0.id) && !pendingDeletionKeys.contains($0.id) }
            .sorted { (archivedSessions.date($0.id) ?? .distantPast) > (archivedSessions.date($1.id) ?? .distantPast) }
    }

    /// Hides a task from the sidebar, keeping its history, and puts away the workspace Native made
    /// for it. Undo (the toast or ⌘Z) brings both back, and Redo archives it again.
    func archiveSession(_ key: SessionKey, undoManager: UndoManager? = nil) async {
        guard let listed = catalog.lookup(key), !archivedSessions.contains(key) else { return }
        _ = taskActionRoute(for: key)
        let title = titleOfSession(key)
        let selected = moveAfterArchiving([key])
        archivedSessions.set(key, archived: true)
        // On the undo stack at once, in the order things were done, so ⌘Z brings the task back while
        // its workspace is still being put away. The toast adds the workspace result when it finishes.
        let action = offerUndo("Archived “\(title)”.", name: "Archive Task", undoManager: undoManager) { model in
            model.undoArchive([key], selecting: selected)
        } redo: { model in
            model.archiveAgain([key])
        }
        let detail = await putAwayWorkspace(of: key, titled: title, in: listed.project)
        guard action.canUndo else { return }
        action.message += detail
    }

    /// Puts away the workspace of a task just archived, returning what was done as a sentence to
    /// add to the undo message (or nothing), and reporting a failure with the project. Internal only
    /// for AppModel+BulkActions.swift.
    func putAwayWorkspace(of key: SessionKey, titled title: String, in projectID: Project.ID) async -> String {
        // A workspace that couldn't be brought back last time stays put away now.
        problems.resolve(.workspaceRestore(key), in: projectID)
        guard projectID != NoProjectLocation.id, let project = projects.project(projectID) else { return "" }
        do {
            return try await archiveWorkspace(of: key, in: project).map { " " + $0 } ?? ""
        } catch {
            problems.report(
                ProjectProblem(
                    project: project.id, work: .workspaceArchive(key),
                    title: "Couldn't put away “\(title)”'s workspace",
                    recovery: "The task is archived; its workspace is still on disk.",
                    details: error.localizedDescription))
            return ""
        }
    }

    /// Brings an archived task back to the sidebar, with its workspace if Native put one away.
    func unarchiveSession(_ key: SessionKey) async {
        guard beginUnarchiving(key) else { return }
        await finishUnarchiving(key)
    }

    /// The visible state changes before any suspension, so an immediate Redo sees all restored tasks.
    func beginUnarchiving(_ key: SessionKey) -> Bool {
        guard archivedSessions.contains(key), let route = taskActionRoute(for: key) else { return false }
        archiveDatesAwaitingRestore[key] = archivedSessions.date(key)
        archivedSessions.set(key, archived: false)
        // A workspace that couldn't be put away is where it should be now.
        problems.resolve(.workspaceArchive(key), in: route.project.id)
        return true
    }

    func finishUnarchiving(_ key: SessionKey) async {
        do {
            try await restoreWorkspace(of: key)
        } catch {
            reportRestoreFailure(of: key, error)
        }
    }

    /// Brings back the workspace Native put away for a task, if there is one and the task is still
    /// unarchived when its turn comes. What brings it back is kept with the project, so a failure
    /// can be retried. Internal only for AppModel+Problems.swift.
    func restoreWorkspace(of key: SessionKey) async throws {
        if catalog.lookup(key)?.project == NoProjectLocation.id { return }
        guard let route = taskActionRoute(for: key) else { throw TaskActionRoute.Failure.missingRoute }
        let task = ArchivedTaskDetails(title: route.title, archivedAt: archiveDatesAwaitingRestore[key])
        try await inWorkspaceOrder(using: route) {
            // Archived again before its turn came: it stays put away.
            guard !self.archivedSessions.contains(key), !self.deletedSessions.contains(key) else { return }
            let provider = try self.workspaceProvider(for: route)
            if let folder = route.workspace {
                try await provider?.restoreWorkspace(at: folder, in: route.project, task: task)
            }
            self.archiveDatesAwaitingRestore[key] = nil
        }
    }

    /// Finishes bringing back the workspaces of tasks unarchived as Native quit (Undo, then quit at
    /// once): each is in the sidebar, and what brings its workspace back is still kept with its
    /// project. Run once at launch.
    func resumeWorkspaceRestores() async {
        for project in projects.all {
            let routes = allSessions(in: project.id).filter { !archivedSessions.contains($0.id) }
                .compactMap { taskActionRoute(for: $0.id) }
            for owned in Dictionary(grouping: routes, by: \.owner).values {
                guard let first = owned.first, let provider = try? workspaceProvider(for: first) else { continue }
                let folders = await provider.archivedWorkspaceFolders(of: first.project)
                for route in owned
                where route.folder.map({ folder in
                    folders.contains {
                        route.owner == .local
                            ? SessionFolder.isSame($0.folderPath, folder.folderPath)
                            : RemoteHost.plain($0.folderPath) == RemoteHost.plain(folder.folderPath)
                    }
                }) == true {
                    do {
                        try await restoreWorkspace(of: route.key)
                    } catch {
                        reportRestoreFailure(of: route.key, error)
                    }
                }
            }
        }
    }

    private func reportRestoreFailure(of key: SessionKey, _ error: any Error) {
        // Without a project, the task isn't in the sidebar to come back to either.
        let route = taskActionRoute(for: key)
        guard let project = route?.project.id ?? catalog.lookup(key)?.project else { return }
        let title = route?.title ?? titleOfSession(key)
        if let failure = error as? TaskWorkspaceRestoreFailure {
            // Nothing says how to rebuild it, so Retry alone wouldn't help: say what's missing, and
            // offer the project's folder instead.
            let saved = failure.savedWork.map { " " + $0 } ?? ""
            problems.report(
                ProjectProblem(
                    project: project, work: .workspaceRestore(key),
                    title: "Couldn't rebuild “\(title)”'s worktree",
                    recovery: "The task is back with its conversation. " + (failure.errorDescription ?? "") + saved,
                    suggestion: failure.suggestion,
                    alternative: .startInProjectFolder(key)))
            return
        }
        problems.report(
            ProjectProblem(
                project: project, work: .workspaceRestore(key),
                title: "Couldn't restore “\(title)”'s workspace",
                recovery: "The task is back, and the checkpoint of its work is still saved.",
                details: error.localizedDescription))
    }

    /// Removes a task from Native: the agent's own copy too when it can delete sessions, and the
    /// workspace Native made for it (after a checkpoint). Nothing is removed until the undo window
    /// passes; undoing in time brings the task back untouched, and Redo deletes it again.
    func deleteSession(_ key: SessionKey, undoManager: UndoManager? = nil, confirmedFolder: Bool = false) {
        guard canDelete(key) else { return }
        if !confirmedFolder, offersProjectFolderTasks, usesProjectFolder(key) {
            projectFolderDeletion = ProjectFolderDeletion(title: "Delete this task?") { [weak self, weak undoManager] in
                self?.deleteSession(key, undoManager: undoManager, confirmedFolder: true)
            }
            return
        }
        let message =
            "Deleted “\(titleOfSession(key))”."
            + (offersProjectFolderTasks && usesProjectFolder(key)
                ? " The project folder and branch are unchanged." : "")
        let action = UndoableAction(message, name: "Delete Task", undoManager: undoManager) { [weak self] _ in
            self?.cancelDeletion(of: key)
        } redo: { [weak self] action in
            self?.scheduleDeletion(of: key, undo: action)
        }
        scheduleDeletion(of: key, undo: action)
        lastUndoable = action
    }

    /// Whether a task can be deleted: it's listed, and not already waiting out a deletion. Internal
    /// only for AppModel+BulkActions.swift, as are `scheduleDeletion` and `cancelDeletion`.
    func canDelete(_ key: SessionKey) -> Bool {
        catalog.lookup(key) != nil && pendingDeletions[key] == nil
    }

    /// Takes a task off the sidebar and deletes it once the undo window passes, unless the deletion
    /// is cancelled first. From then on `undo` can't bring it back, so it leaves the undo stack.
    func scheduleDeletion(of key: SessionKey, undo: UndoableAction) {
        guard let listed = catalog.lookup(key), pendingDeletions[key] == nil,
            let route = taskActionRoute(for: key)
        else { return }
        leave(key, in: listed.project)
        pendingDeletions[key] = Task { [weak self] in
            try? await Task.sleep(for: Self.deletionGracePeriod)
            guard !Task.isCancelled else { return }
            undo.withdraw()
            await self?.carryOutDeletion(using: route)
        }
    }

    func cancelDeletion(of key: SessionKey) {
        pendingDeletions.removeValue(forKey: key)?.cancel()
    }

    private func carryOutDeletion(using route: TaskActionRoute) async {
        let key = route.key
        let projectID = route.project.id
        guard pendingDeletions[key] != nil else { return }
        defer { pendingDeletions[key] = nil }
        do {
            try await releaseCoordinatorAssignments(beforeDeleting: key)
        } catch {
            actionFailure = ActionFailure("Couldn't Delete Coordinator", error.localizedDescription)
            return
        }
        let hadPrivateFiles = scratchTasks.folder(for: NoProjectLocation.key(key)) != nil
        if hadPrivateFiles, !(await removePrivateTaskFiles(using: route)) { return }
        let title = route.title
        deletedSessions.insert(key)
        archivedSessions.set(key, archived: false)
        unread.set(key, unread: false)
        catalog.remove(key)
        catalog.remote[key] = nil
        ordering.unpin(key)
        // Putting its workspace away or bringing it back no longer matters: deleting removes it.
        problems.resolve(.workspaceArchive(key), in: projectID)
        problems.resolve(.workspaceRestore(key), in: projectID)
        let agentName =
            taskRuntime(for: route.owner, agent: key.agent)?.agent.displayName
            ?? plugins.agent(key.agent)?.displayName ?? key.agent.rawValue
        do {
            try await deleteAgentCopy(using: route, startingIfNeeded: false)
        } catch {
            problems.report(
                ProjectProblem(
                    project: projectID, work: .agentCopyDeletion(key),
                    title: "\(agentName) couldn't delete “\(title)”",
                    recovery: "The task is gone from Native, but \(agentName) still has its copy.",
                    details: error.localizedDescription))
        }
        do {
            try await deleteWorkspace(using: route)
        } catch {
            problems.report(
                ProjectProblem(
                    project: projectID, work: .workspaceDeletion(key, folder: route.folder ?? route.project.url),
                    title: "Couldn't remove “\(title)”'s workspace",
                    recovery: "The task is deleted, but its workspace is still on disk.",
                    details: error.localizedDescription))
        }
    }

    // MARK: - Projects

    /// Hides a project, with its tasks, from the sidebar. Undo puts it back where it was, and Redo
    /// hides it again.
    func archiveProject(_ id: Project.ID, undoManager: UndoManager? = nil) {
        guard let project = projects.project(id) else { return }
        leaveProject(id)
        let index = projects.archive(id)
        offerUndo("Archived “\(project.name)”.", name: "Archive Project", undoManager: undoManager) { model in
            model.unarchiveProject(id, at: index)
        } redo: { model in
            model.leaveProject(id)
            _ = model.projects.archive(id)
        }
    }

    func unarchiveProject(_ id: Project.ID, at index: Int? = nil) {
        projects.unarchive(id, at: index)
        if let project = projects.project(id) {
            Task { await refreshSessions(in: project) }
        }
    }

    /// Removes a project from Native, archived or not. The user's folder is never touched; only the
    /// workspaces Native made for its tasks are removed, once the undo window passes.
    func deleteProject(_ id: Project.ID, undoManager: UndoManager? = nil) {
        guard let project = projects.project(id) ?? projects.archived.first(where: { $0.id == id }) else { return }
        let wasArchived = projects.project(id) == nil
        let index = wasArchived ? nil : projects.archive(id)
        leaveProject(id)
        let action = UndoableAction(
            "Deleted “\(project.name)”. Its folder wasn't touched.", name: "Delete Project", undoManager: undoManager
        ) { [weak self] _ in
            guard let self else { return }
            pendingProjectDeletions.removeValue(forKey: id)?.cancel()
            if !wasArchived {
                unarchiveProject(id, at: index)
            }
        } redo: { [weak self] action in
            guard let self else { return }
            if !wasArchived {
                leaveProject(id)
                _ = projects.archive(id)
            }
            scheduleDeletion(of: project, undo: action)
        }
        scheduleDeletion(of: project, undo: action)
        lastUndoable = action
    }

    /// Removes an archived project once the undo window passes, unless the deletion is cancelled
    /// first. From then on `undo` can't bring it back, so it leaves the undo stack.
    private func scheduleDeletion(of project: Project, undo: UndoableAction) {
        let id = project.id
        pendingProjectDeletions[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.deletionGracePeriod)
            guard !Task.isCancelled, let self, pendingProjectDeletions.removeValue(forKey: id) != nil else { return }
            undo.withdraw()
            projects.removeArchived(id)
            catalog.remove(project: id)
            problems.resolveAll { $0.project == id }
            ordering.forget(id)
            try? await taskWorkspaces?.deleteWorkspaces(of: project)
        }
    }

    // MARK: - Helpers

    /// Internal only for AppModel+BulkActions.swift, as is `leave`.
    func titleOfSession(_ key: SessionKey) -> String {
        sessions.session(key)?.displayTitle
            ?? titles.title(
                for: SessionTitles.Key(agent: key.agent, session: key.id), agentTitle: catalog.lookup(key)?.info.title)
            ?? "New Task"
    }

    /// Moves off a task that's leaving the sidebar, to its project's home.
    func leave(_ key: SessionKey, in project: Project.ID) {
        if selection == key {
            focusProject(project)
        }
    }

    private func leaveProject(_ id: Project.ID) {
        if let selection, catalog.lookup(selection)?.project == id {
            self.selection = nil
        }
        if focusedProjectID == id {
            focusedProjectID = nil
        }
    }

    /// Puts away the workspace Native made for a task, if it has one and the task is still archived
    /// when its turn comes. Returns what was done, for the toast. Internal only for
    /// AppModel+Problems.swift.
    func archiveWorkspace(of key: SessionKey, in project: Project) async throws -> String? {
        guard let route = taskActionRoute(for: key) else { throw TaskActionRoute.Failure.missingRoute }
        return try await inWorkspaceOrder(using: route) {
            // Unarchived before its turn came (Undo while a bulk archive works): it stays.
            guard self.archivedSessions.contains(key), !self.deletedSessions.contains(key) else { return nil }
            let provider = try self.workspaceProvider(for: route)
            guard let folder = route.workspace else { return nil }
            return try await provider?.archiveWorkspace(at: folder, in: route.project)
        }
    }

    /// The folder a task runs in, unless it's the project's own, which Native never puts away.
    /// Internal only for AppModel+RemovedWorkspaces.swift, as is `inWorkspaceOrder`.
    func taskFolder(of key: SessionKey, in project: Project) -> URL? {
        guard taskActionOwner(for: key) == .local else { return nil }
        guard
            let folder = sessions.session(key)?.cwd
                ?? catalog.lookup(key).map({ URL(filePath: $0.info.cwd, directoryHint: .isDirectory) }),
            !SessionFolder.isSame(folder.folderPath, project.path)
        else { return nil }
        return folder
    }

    /// Runs `work` on a folder's workspace after whatever was already started on it, so putting it
    /// away and bringing it back happen in the order they were asked for (Undo pressed while a bulk
    /// archive is still removing it), and two tasks in one folder don't bring it back twice.
    func inWorkspaceOrder<Value: Sendable>(
        at folder: URL, _ work: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let path = folder.standardizedFileURL.path(percentEncoded: false)
        return try await inWorkspaceOrder(key: path, work)
    }

    func inWorkspaceOrder<Value: Sendable>(
        key path: String, _ work: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let previous = workspaceWork[path]
        let task = Task { @MainActor in
            await previous?.value
            return try await work()
        }
        let finished = Task { @MainActor in _ = try? await task.value }
        workspaceWork[path] = finished
        defer {
            if workspaceWork[path] == finished { workspaceWork[path] = nil }
        }
        return try await task.value
    }

}
