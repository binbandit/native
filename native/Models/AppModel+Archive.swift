import ACP
import Foundation

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
            .filter { archivedSessions.contains($0.id) }
            .sorted { (archivedSessions.date($0.id) ?? .distantPast) > (archivedSessions.date($1.id) ?? .distantPast) }
    }

    /// Hides a task from the sidebar, keeping its history, and puts away the workspace Native made
    /// for it. Undo (the toast or ⌘Z) brings both back.
    func archiveSession(_ key: SessionKey, undoManager: UndoManager? = nil) async {
        guard let listed = catalog.lookup(key), !archivedSessions.contains(key) else { return }
        let title = titleOfSession(key)
        archivedSessions.set(key, archived: true)
        leave(key, in: listed.project)
        let detail = await putAwayWorkspace(of: key, titled: title, in: listed.project)
        offerUndo("Archived “\(title)”.\(detail)", name: "Archive Task", undoManager: undoManager) { model in
            Task { await model.unarchiveSession(key) }
        }
    }

    /// Puts away the workspace of a task just archived, returning what was done as a sentence to
    /// add to the undo message (or nothing), and reporting a failure with the project. Internal only
    /// for AppModel+BulkActions.swift.
    func putAwayWorkspace(of key: SessionKey, titled title: String, in projectID: Project.ID) async -> String {
        // A workspace that couldn't be brought back last time stays put away now.
        problems.resolve(.workspaceRestore(key), in: projectID)
        guard let project = projects.project(projectID) else { return "" }
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
        guard archivedSessions.contains(key) else { return }
        archiveDatesAwaitingRestore[key] = archivedSessions.date(key)
        archivedSessions.set(key, archived: false)
        if let project = catalog.lookup(key)?.project {
            // A workspace that couldn't be put away is where it should be now.
            problems.resolve(.workspaceArchive(key), in: project)
        }
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
        guard let listed = catalog.lookup(key), let project = projects.project(listed.project),
            let folder = taskFolder(of: key, in: project)
        else { return }
        let task = ArchivedTaskDetails(title: titleOfSession(key), archivedAt: archiveDatesAwaitingRestore[key])
        try await inWorkspaceOrder(at: folder) {
            // Archived again before its turn came: it stays put away.
            guard !self.archivedSessions.contains(key) else { return }
            try await self.taskWorkspaces?.restoreWorkspace(at: folder, in: project, task: task)
            self.archiveDatesAwaitingRestore[key] = nil
        }
    }

    /// Finishes bringing back the workspaces of tasks unarchived as Native quit (Undo, then quit at
    /// once): each is in the sidebar, and what brings its workspace back is still kept with its
    /// project. Run once at launch.
    func resumeWorkspaceRestores() async {
        guard let provider = taskWorkspaces else { return }
        for project in projects.all {
            let folders = await provider.archivedWorkspaceFolders(of: project)
            guard !folders.isEmpty else { continue }
            let unarchived = allSessions(in: project.id).filter { summary in
                !archivedSessions.contains(summary.id)
                    && folders.contains { SessionFolder.isSame($0.folderPath, summary.info.cwd) }
            }
            for summary in unarchived {
                do {
                    try await restoreWorkspace(of: summary.id)
                } catch {
                    reportRestoreFailure(of: summary.id, error)
                }
            }
        }
    }

    private func reportRestoreFailure(of key: SessionKey, _ error: any Error) {
        // Without a project, the task isn't in the sidebar to come back to either.
        guard let project = catalog.lookup(key)?.project else { return }
        if let failure = error as? TaskWorkspaceRestoreFailure {
            // Nothing says how to rebuild it, so Retry alone wouldn't help: say what's missing, and
            // offer the project's folder instead.
            let saved = failure.savedWork.map { " " + $0 } ?? ""
            problems.report(
                ProjectProblem(
                    project: project, work: .workspaceRestore(key),
                    title: "Couldn't rebuild “\(titleOfSession(key))”'s worktree",
                    recovery: "The task is back with its conversation. " + (failure.errorDescription ?? "") + saved,
                    suggestion: failure.suggestion,
                    alternative: .startInProjectFolder(key)))
            return
        }
        problems.report(
            ProjectProblem(
                project: project, work: .workspaceRestore(key),
                title: "Couldn't restore “\(titleOfSession(key))”'s workspace",
                recovery: "The task is back, and the checkpoint of its work is still saved.",
                details: error.localizedDescription))
    }

    /// Removes a task from Native: the agent's own copy too when it can delete sessions, and the
    /// workspace Native made for it (after a checkpoint). Nothing is removed until the undo window
    /// passes; undoing in time brings the task back untouched.
    func deleteSession(_ key: SessionKey, undoManager: UndoManager? = nil) {
        let title = titleOfSession(key)
        guard scheduleDeletion(of: key) else { return }
        offerUndo("Deleted “\(title)”.", name: "Delete Task", undoManager: undoManager) { model in
            model.pendingDeletions.removeValue(forKey: key)?.cancel()
        }
    }

    /// Takes a task off the sidebar and deletes it once the undo window passes, unless the deletion
    /// is cancelled (`pendingDeletions`). Returns whether it was scheduled. Internal only for
    /// AppModel+BulkActions.swift.
    func scheduleDeletion(of key: SessionKey) -> Bool {
        guard let listed = catalog.lookup(key), pendingDeletions[key] == nil else { return false }
        leave(key, in: listed.project)
        pendingDeletions[key] = Task { [weak self] in
            try? await Task.sleep(for: Self.deletionGracePeriod)
            guard !Task.isCancelled else { return }
            await self?.carryOutDeletion(of: key, in: listed.project)
        }
        return true
    }

    private func carryOutDeletion(of key: SessionKey, in projectID: Project.ID) async {
        guard pendingDeletions.removeValue(forKey: key) != nil else { return }
        let title = titleOfSession(key)
        let folder =
            sessions.session(key)?.cwd
            ?? catalog.lookup(key).map { URL(filePath: $0.info.cwd, directoryHint: .isDirectory) }
        deletedSessions.insert(key)
        archivedSessions.set(key, archived: false)
        unread.set(key, unread: false)
        catalog.remove(key)
        ordering.unpin(key)
        // Putting its workspace away or bringing it back no longer matters: deleting removes it.
        problems.resolve(.workspaceArchive(key), in: projectID)
        problems.resolve(.workspaceRestore(key), in: projectID)
        // The agent's copy goes too when it's running; a stopped agent isn't started just for this.
        if let runtime = runtimes[key.agent], let connection = runtime.connection,
            runtime.capabilities?.deleteSessions == true
        {
            do {
                _ = try await connection.send(DeleteSessionRequest(sessionId: key.id))
            } catch {
                problems.report(
                    ProjectProblem(
                        project: projectID, work: .agentCopyDeletion(key),
                        title: "\(runtime.agent.displayName) couldn't delete “\(title)”",
                        recovery: "The task is gone from Native, but \(runtime.agent.displayName) still has its copy.",
                        details: error.localizedDescription))
            }
        }
        if let folder, let project = projects.project(projectID), !SessionFolder.isSame(folder.folderPath, project.path)
        {
            do {
                try await taskWorkspaces?.deleteWorkspace(at: folder, in: project)
            } catch {
                problems.report(
                    ProjectProblem(
                        project: projectID, work: .workspaceDeletion(key, folder: folder),
                        title: "Couldn't remove “\(title)”'s workspace",
                        recovery: "The task is deleted, but its workspace is still on disk.",
                        details: error.localizedDescription))
            }
        }
        if let project = projects.project(projectID) {
            await taskWorkspaces?.taskWasDeleted(key, title: title, folder: folder ?? project.url, in: project)
        }
    }

    // MARK: - Projects

    /// Hides a project, with its tasks, from the sidebar. Undo puts it back where it was.
    func archiveProject(_ id: Project.ID, undoManager: UndoManager? = nil) {
        guard let project = projects.project(id) else { return }
        leaveProject(id)
        let index = projects.archive(id)
        offerUndo("Archived “\(project.name)”.", name: "Archive Project", undoManager: undoManager) { model in
            model.unarchiveProject(id, at: index)
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
        pendingProjectDeletions[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.deletionGracePeriod)
            guard !Task.isCancelled, let self, pendingProjectDeletions.removeValue(forKey: id) != nil else { return }
            projects.removeArchived(id)
            catalog.remove(project: id)
            problems.resolveAll { $0.project == id }
            ordering.forget(id)
            try? await taskWorkspaces?.deleteWorkspaces(of: project)
        }
        offerUndo(
            "Deleted “\(project.name)”. Its folder wasn't touched.", name: "Delete Project", undoManager: undoManager
        ) { model in
            model.pendingProjectDeletions.removeValue(forKey: id)?.cancel()
            if !wasArchived {
                model.unarchiveProject(id, at: index)
            }
        }
    }

    // MARK: - Helpers

    /// Internal only for AppModel+BulkActions.swift, as are `leave` and `offerUndo`.
    func titleOfSession(_ key: SessionKey) -> String {
        sessions.session(key)?.displayTitle
            ?? titles.title(
                for: SessionTitles.Key(agent: key.agent, session: key.id), agentTitle: catalog.lookup(key)?.info.title)
            ?? "New Session"
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
        guard let folder = taskFolder(of: key, in: project) else { return nil }
        return try await inWorkspaceOrder(at: folder) {
            // Unarchived before its turn came (Undo while a bulk archive works): it stays.
            guard self.archivedSessions.contains(key) else { return nil }
            return try await self.taskWorkspaces?.archiveWorkspace(at: folder, in: project)
        }
    }

    /// The folder a task runs in, unless it's the project's own, which Native never puts away.
    private func taskFolder(of key: SessionKey, in project: Project) -> URL? {
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
    private func inWorkspaceOrder<Value: Sendable>(
        at folder: URL, _ work: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let path = folder.standardizedFileURL.path(percentEncoded: false)
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

    /// Shows the undo toast and registers the same undo with the window's undo manager.
    func offerUndo(
        _ message: String, name: String, undoManager: UndoManager?, undo: @escaping (AppModel) -> Void
    ) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { undo(model) }
        }
        undoManager?.setActionName(name)
        lastUndoable = UndoableAction(message: message) { [weak self] in
            guard let self else { return }
            undo(self)
        }
    }
}
