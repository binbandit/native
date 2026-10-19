import Foundation
import Git

// Cleaning up what the user included, in the background, item by item: stale records, then
// worktrees (through the archive path, so teardown scripts run and Unarchive works), then branches,
// then leftover folders. A failed item is left as it was and says why in the sheet.
extension GitCleanupModel {
    var failureCount: Int {
        states.values.count { if case .failed = $0 { true } else { false } }
    }

    var doneCount: Int {
        states.values.count { $0 == .done }
    }

    func cleanUp() {
        let chosen = included
        guard phase == .review, !chosen.isEmpty else { return }
        phase = .running
        states = [:]
        work = Task { await run(chosen) }
    }

    private func run(_ chosen: [GitCleanupItem]) async {
        var record = GitCleanupUndo()
        let root = project.url
        let git = services.git
        // A branch a stale record holds can't be deleted until the record is gone.
        for item in chosen {
            guard case .staleRecord(let path) = item.id else { continue }
            await step(item) { try await git.forgetStaleWorktree(at: path, in: root) }
        }
        for item in chosen {
            guard case .worktree(let path) = item.id else { continue }
            states[item.id] = .working
            states[item.id] = await putAway(item, at: path, into: &record)
        }
        for item in chosen {
            guard case .branch(let name) = item.id else { continue }
            if let requirement = item.requires, states[requirement] != .done {
                states[item.id] = .failed("Kept: it's still checked out in the worktree that couldn't be removed.")
                continue
            }
            await step(item) {
                // Archiving its task may have deleted it already (Settings ▸ Git), keeping a copy
                // that Unarchive restores.
                guard await git.hasBranch(name, in: root) else { return }
                try await git.deleteMergedBranch(name, in: root)
                record.branches.append(name)
            }
        }
        #if os(macOS)
        for item in chosen {
            guard case .leftoverFolder(let path) = item.id else { continue }
            await step(item) {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: path, resultingItemURL: &trashed)
                if let trashed = trashed as URL? { record.folders.append((path, trashed)) }
            }
        }
        #endif
        git.refresh(folder: root)
        undoRecord = record
        phase = .finished
        onFinished?(self)
    }

    private func step(_ item: GitCleanupItem, _ body: () async throws -> Void) async {
        states[item.id] = .working
        do {
            try await body()
            states[item.id] = .done
        } catch {
            states[item.id] = .failed(Self.describe(error))
        }
    }

    /// A failure in plain words where git's are cryptic, otherwise git's own.
    private static func describe(_ error: any Error) -> String {
        guard let error = error as? GitError, error.failure == .repositoryLocked else {
            return error.localizedDescription
        }
        return "Another git process has the repository locked, so this was left as it was. Try again when it's done."
    }

    /// Archives the worktree's tasks, which removes it the way archiving one does (teardown script,
    /// checkpoint of uncommitted work); a worktree no task works in is put away the same way. On
    /// failure its tasks come back and the worktree stays.
    private func putAway(_ item: GitCleanupItem, at path: URL, into record: inout GitCleanupUndo) async -> ItemState {
        let app = services.app
        let tasks = item.tasks.filter { !app.isArchived($0.key) }
        for task in tasks {
            app.archivedSessions.set(task.key, archived: true)
            app.leave(task.key, in: project.id)
        }
        for task in tasks {
            _ = await app.putAwayWorkspace(of: task.key, titled: task.title, in: project.id)
        }
        let keys = tasks.map(\.key)
        // Archiving reports a workspace it couldn't put away with the project; here the row says so.
        if let problem = app.problems.list(for: project.id).first(where: { problem in
            keys.contains { problem.work == .workspaceArchive($0) }
        }) {
            await app.unarchiveSessions(keys)
            return .failed(problem.details ?? problem.title)
        }
        record.tasks += keys
        // No task here, or its tasks run in a folder inside it: put the worktree itself away.
        guard await services.git.isTaskWorktree(path, of: project.url) else { return .done }
        do {
            guard let provider = app.taskWorkspaces, try await provider.archiveWorkspace(at: path, in: project) != nil
            else { return .failed("Native couldn't remove this worktree.") }
            record.worktrees.append(path)
            return .done
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Undo

    /// Offers the run's undo as the window's toast (and ⌘Z), once.
    func offerUndo() {
        guard let record = undoRecord, !record.isEmpty, !isUndoOffered else { return }
        isUndoOffered = true
        let done = doneCount
        var message =
            failureCount == 0
            ? "Cleaned up \(done == 1 ? "1 item" : "\(done) items") in “\(project.name)”"
            : "Cleaned up \(done) of \(states.count) items in “\(project.name)”"
        let bytes = items.filter { states[$0.id] == .done }.compactMap(\.bytes).reduce(0, +)
        if bytes > 0 { message += ", reclaiming \(DSFormat.fileSize(bytes))" }
        services.app.offerUndo(message + ".", name: "Clean Up Merged", undoManager: undoManager) {
            [self] _ in
            Task { await undo() }
        }
    }

    /// The sheet's Undo, after a run with failures: takes the run back instead of offering it.
    func undoFromSheet() {
        isUndoOffered = true
        work = Task { await undo() }
    }

    /// Brings back what the run removed: branches at their old commits with their config, tasks
    /// with their worktrees and uncommitted work, and folders from the Trash.
    func undo() async {
        guard let record = undoRecord else { return }
        undoRecord = nil
        let root = project.url
        var failures: [String] = []
        for branch in record.branches {
            do {
                try await services.git.restoreDeletedBranch(branch, in: root)
            } catch {
                failures.append("\(branch): \(error.localizedDescription)")
            }
        }
        // Each task that can't get its worktree back says so with the project.
        await services.app.unarchiveSessions(record.tasks)
        for path in record.worktrees {
            do {
                try await services.app.taskWorkspaces?.restoreWorkspace(at: path, in: project)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        #if os(macOS)
        for folder in record.folders {
            do {
                try FileManager.default.moveItem(at: folder.trashed, to: folder.original)
            } catch {
                failures.append("\(folder.original.lastPathComponent): \(error.localizedDescription)")
            }
        }
        #endif
        services.git.refresh(folder: root)
        if !failures.isEmpty {
            services.app.actionFailure = AppModel.ActionFailure(
                "Couldn't Undo All of the Clean Up",
                "Everything else is back. These couldn't be restored:\n" + failures.joined(separator: "\n"))
        }
    }
}
