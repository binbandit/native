import ACP
import Foundation

// Tasks whose workspaces were removed outside Native (a worktree deleted in Terminal or by another
// tool, or pruned): the agents still list them, in folders that are gone. Each is decided the way
// Clean Up Merged decides branches (`TaskWorkspaceProvider.removedWorkspaces`): done work is archived,
// with Undo, and stays findable in Archived and search; work that isn't done stays in sight with
// Restore Worktree and Archive (`removedWorkspaces`). Nothing is deleted, and since the decision
// is made again from the repository, a relaunch doesn't bring archived ones back.
extension AppModel {
    /// Checks a moment after the listed sessions change and whenever the user comes back to Native
    /// (a worktree removed in Terminal changes no listing). Run once at launch.
    func watchRemovedWorkspaces() {
        scheduleRemovedWorkspaceCheck()
        _ = NotificationCenter.default.addObserver(
            forName: PlatformApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRemovedWorkspaceCheck() }
        }
        trackListedSessions()
    }

    /// Brings back a removed workspace on its branch, set up like a new task's.
    func restoreRemovedWorkspace(_ key: SessionKey) async {
        guard let branch = removedWorkspaces[key]?.branch, !restoringRemovedWorkspaces.contains(key),
            let listed = catalog.lookup(key), let project = projects.project(listed.project),
            let folder = taskFolder(of: key, in: project)
        else { return }
        restoringRemovedWorkspaces.insert(key)
        defer { restoringRemovedWorkspaces.remove(key) }
        do {
            try await inWorkspaceOrder(at: folder) {
                try await self.taskWorkspaces?.restoreRemovedWorkspace(at: folder, branch: branch, in: project)
            }
            removedWorkspaces[key] = nil
            problems.resolve(.workspaceRestore(key), in: project.id)
        } catch {
            problems.report(
                ProjectProblem(
                    project: project.id, work: .workspaceRestore(key),
                    title: "Couldn't restore “\(titleOfSession(key))”'s worktree",
                    recovery: "The task is as it was, with its worktree removed.",
                    details: error.localizedDescription))
        }
    }

    // MARK: - Checking

    private func trackListedSessions() {
        withObservationTracking {
            for project in projects.all {
                _ = allSessions(in: project.id)
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleRemovedWorkspaceCheck()
                self?.trackListedSessions()
            }
        }
    }

    /// One check at a time, a moment after the last ask: listings arrive agent by agent.
    private func scheduleRemovedWorkspaceCheck() {
        isRemovedWorkspaceCheckDue = true
        guard removedWorkspaceCheck == nil else { return }
        removedWorkspaceCheck = Task { [weak self] in
            while let self, self.isRemovedWorkspaceCheckDue {
                try? await Task.sleep(for: .seconds(1))
                self.isRemovedWorkspaceCheckDue = false
                var done: [DoneTask] = []
                for project in self.projects.all {
                    done += await self.checkRemovedWorkspaces(in: project)
                }
                self.archive(done)
            }
            self?.removedWorkspaceCheck = nil
        }
    }

    /// Decides the project's tasks whose workspaces are gone, keeping those whose work isn't done
    /// in `removedWorkspaces` and returning those whose work is.
    private func checkRemovedWorkspaces(in project: Project) async -> [DoneTask] {
        guard let provider = taskWorkspaces else { return [] }
        let listed = allSessions(in: project.id)
        let tasks = listed.compactMap { summary -> (key: SessionKey, folder: URL, title: String)? in
            guard isSettled(summary.id), let folder = taskFolder(of: summary.id, in: project) else { return nil }
            return (summary.id, folder, titleOfSession(summary.id))
        }
        let fates =
            tasks.isEmpty
            ? [:] : await provider.removedWorkspaces(among: tasks.map { ($0.folder, $0.title) }, in: project)
        var kept: [SessionKey: RemovedWorkspace] = [:]
        var done: [DoneTask] = []
        // Archived, brought back or deleted while Native looked: that settles it instead.
        for task in tasks where isSettled(task.key) {
            switch fates[task.folder] {
            case .kept(let removed)?: kept[task.key] = removed
            case .done(let reason)?:
                done.append(DoneTask(key: task.key, project: project, title: task.title, reason: reason))
            case nil: break
            }
        }
        let keys = Set(listed.map(\.id))
        let updated = removedWorkspaces.filter { !keys.contains($0.key) }.merging(kept) { _, new in new }
        if updated != removedWorkspaces {
            removedWorkspaces = updated
        }
        return done
    }

    /// Not archived, and not being archived, brought back, restored or deleted.
    private func isSettled(_ key: SessionKey) -> Bool {
        guard !archivedSessions.contains(key), !pendingDeletionKeys.contains(key),
            archiveDatesAwaitingRestore[key] == nil, !restoringRemovedWorkspaces.contains(key)
        else { return false }
        guard let folder = catalog.lookup(key).map({ URL(filePath: $0.info.cwd, directoryHint: .isDirectory) }) else {
            return false
        }
        return workspaceWork[folder.standardizedFileURL.path(percentEncoded: false)] == nil
    }

    /// Archives tasks whose work is done, saying so with Undo, which brings them back the way
    /// Unarchive does (with their worktree, on their branch, when it's still there).
    private func archive(_ done: [DoneTask]) {
        guard !done.isEmpty else { return }
        for task in done {
            archivedSessions.set(task.key, archived: true)
            leave(task.key, in: task.project.id)
        }
        let message =
            done.count == 1
            ? "Archived “\(done[0].title)”: its worktree was removed, and \(done[0].reason)."
            : "Archived \(done.count) tasks whose worktrees were removed and whose work is done."
        let keys = done.map(\.key)
        offerUndo(message, name: done.count == 1 ? "Archive Task" : "Archive Tasks", undoManager: nil) { model in
            Task { await model.unarchiveSessions(keys) }
        }
    }
}

/// A task whose workspace was removed and whose work is done, to archive.
private struct DoneTask {
    let key: SessionKey
    let project: Project
    let title: String
    let reason: String
}
