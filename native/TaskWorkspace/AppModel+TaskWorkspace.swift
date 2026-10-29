import ACP
import Foundation
import NativeHostClient

extension AppModel {
    func workspaceOptions(for source: SessionModel) async throws -> [TaskWorkspaceOption] {
        guard source.canChangeWorkspace else { throw workspaceChangeUnavailable }
        let (provider, project) = try workspaceProvider(for: source)
        return try await provider.workspaceOptions(in: project, current: source.cwd)
    }

    /// Prepare the replacement before retiring the empty conversation, so failure keeps the draft.
    @discardableResult
    func changeWorkspace(of source: SessionModel, to choice: TaskWorkspaceChoice) async throws -> SessionModel {
        guard source.canChangeWorkspace else { throw workspaceChangeUnavailable }
        let (provider, project) = try workspaceProvider(for: source)
        source.isChangingWorkspace = true
        defer {
            source.isChangingWorkspace = false
            if let host = source.host, let current = sessions.session(host: host.id), current.cwd == source.cwd {
                current.isChangingWorkspace = false
            }
        }
        // Keep preparation, publication and cleanup in one project lane. A second task must not
        // select the old branch between the unused check and its worktree's removal.
        let previous = workspacePreparations[project.id]
        let work = Task {
            await previous?.value
            return try await performWorkspaceChange(of: source, to: choice, provider: provider, project: project)
        }
        workspacePreparations[project.id] = Task { _ = try? await work.value }
        return try await work.value
    }

    private func performWorkspaceChange(
        of source: SessionModel, to choice: TaskWorkspaceChoice, provider: any TaskWorkspaceProvider, project: Project
    ) async throws -> SessionModel {
        var preparedFolder: URL?
        var replacement: SessionModel?
        do {
            guard let runtime = await ensureRunning(for: source.key) else {
                throw TaskWorkspaceSelectionError("The task's agent is unavailable. Restart it and try again.")
            }
            try validateWorkspaceChange(source)
            let folder = try await provider.workspace(for: choice, in: project)
            preparedFolder = folder
            try validateWorkspaceChange(source)
            if SessionFolder.isSame(folder.folderPath, source.cwd.folderPath) { return source }
            let target = try await launcher.start(on: runtime, cwd: folder, project: project.id, continuing: source)
            replacement = target
            target.isChangingWorkspace = true
            // Keep even agents that list empty conversations from exposing a second task.
            deletedSessions.insert(target.key)
            titles.updateConfigChoices(for: source.titleKey) { choices in
                for option in source.configOptions {
                    if case .select(let value, _) = option.kind { choices.choose(option, value: value) }
                }
            }
            await target.adoptConfigChoices(of: source)
            try validateWorkspaceChange(source)
            guard sessions.session(target.key) === target, target.phase == .idle, !target.hasStarted else {
                throw TaskWorkspaceSelectionError("The replacement task stopped while getting ready. Try again.")
            }
            target.draft = source.draft
            target.adoptDiffCommentDrafts(from: source, moving: true)
            target.attachments = source.attachments
            if let title = titles.namedTitle(for: source.titleKey) { titles.rename(target.titleKey, to: title) }
            let info = SessionInfo(sessionId: target.id, cwd: folder.folderPath, title: source.title, updatedAt: .now)
            catalog.remove(source.key)
            let isRemote = target.host.map { launcher.isRemote($0.client) } ?? false
            if !isRemote {
                catalog.add(info, for: target.agent.id, in: project.id)
                unsentSessions.started(target.key)
            }
            ordering.replace(source.key, with: target.key)
            taskPairs.replace(source.key, with: target.key)
            history.replace(source.key, with: target.key)
            earlierConversations.replace(source.key, with: target.key)
            unsentSessions.forget(source.key)
            deletedSessions.insert(source.key)
            deletedSessions.remove(target.key)
            if isRemote {
                rememberRemoteWorkspace(of: target, in: project)
                indexRemoteSessions()
            }
            source.isWorkspaceReplaced = true
            source.isWorkspacePickerRequested = false
            target.isChangingWorkspace = false
            if selection == source.key {
                selection = target.key
                target.wantsComposerFocus = true
            }
            let closed = await closeWorkspaceConversation(source)
            if closed {
                await cleanUnusedWorkspace(source.cwd, provider: provider, project: project, keeping: target)
            } else {
                target.addNotice(
                    "Workspace changed. The previous worktree was kept because its agent could not be closed.",
                    isError: false)
            }
            return target
        } catch {
            var closed = true
            if let replacement { closed = await closeWorkspaceConversation(replacement) }
            if closed, let preparedFolder, !SessionFolder.isSame(preparedFolder.folderPath, source.cwd.folderPath) {
                await cleanUnusedWorkspace(preparedFolder, provider: provider, project: project, keeping: source)
            }
            throw error
        }
    }

    private func validateWorkspaceChange(_ source: SessionModel) throws {
        if let reason = workspaceChangeBlock(source) { throw TaskWorkspaceSelectionError(reason) }
        guard sessions.session(source.key) === source, !source.hasStarted, !source.hasSubmittedPrompt,
            !source.hasQueuedPrompts, source.phase == .idle, !isArchived(source.key),
            !pendingDeletionKeys.contains(source.key), !deletedSessions.contains(source.key)
        else { throw workspaceChangeUnavailable }
    }

    private var workspaceChangeUnavailable: TaskWorkspaceSelectionError {
        TaskWorkspaceSelectionError("A task's workspace can only change before its first message. Its draft is kept.")
    }

    /// A user-owned checkout may live outside the host's managed folder. Keep its project
    /// association with the paired checkout, so remote history can find it after reconnecting.
    func rememberRemoteWorkspace(of task: SessionModel, in project: Project) {
        guard let link = task.host, let host = hosts.all.first(where: { $0.client === link.client }) else { return }
        projects.update(project.id) { project in
            guard let index = project.checkouts.firstIndex(where: { $0.host == host.id }),
                !host.isTaskFolder(task.cwd.folderPath, ofCheckoutAt: project.checkouts[index].path)
            else { return }
            var folders = project.checkouts[index].taskFolders ?? []
            if !folders.contains(task.cwd.folderPath) { folders.append(task.cwd.folderPath) }
            project.checkouts[index].taskFolders = folders
        }
    }

    /// Resolve by host identity: the same folder path can exist on two different machines.
    private func workspaceProvider(for source: SessionModel) throws -> (any TaskWorkspaceProvider, Project) {
        guard let id = catalog.lookup(source.key)?.project, let project = projects.project(id) else {
            throw TaskWorkspaceSelectionError("The task's project is no longer available.")
        }
        if let link = source.host, launcher.isRemote(link.client) {
            guard let host = hosts.all.first(where: { $0.client === link.client }),
                let provider = host.taskWorkspaces, let path = project.checkoutPath(on: .remote(host.id))
            else { throw TaskWorkspaceSelectionError("Reconnect the task's host to choose a workspace.") }
            return (provider, project.onHost(at: path))
        }
        guard let provider = taskWorkspaces else {
            throw TaskWorkspaceSelectionError("Workspace choices are not available for this project.")
        }
        return (provider, project)
    }

    private func closeWorkspaceConversation(_ original: SessionModel) async -> Bool {
        let source = original.host.flatMap { sessions.session(host: $0.id) } ?? original
        source.isWorkspaceReplaced = true
        sessions.remove(source)
        catalog.remove(source.key)
        unsentSessions.forget(source.key)
        deletedSessions.insert(source.key)
        do {
            if let link = source.host {
                try await link.client.closeSession(link.id, closeInAgent: true)
            } else if agentRuntime(for: source.key)?.capabilities?.closeSessions == true,
                let connection = source.connection
            {
                _ = try await connection.send(CloseSessionRequest(sessionId: source.id))
            } else {
                // Without a close capability an agent may still hold the old folder open.
                return false
            }
            return true
        } catch { return false }
    }

    private func cleanUnusedWorkspace(
        _ folder: URL, provider: any TaskWorkspaceProvider, project: Project, keeping task: SessionModel
    ) async {
        guard
            !catalog.hasTask(in: project.id, at: folder, excluding: deletedSessions.contains),
            sessions.open(in: folder).isEmpty,
            !startingTasks.contains(where: {
                $0.folder.map { SessionFolder.isSame($0.folderPath, folder.folderPath) } ?? false
            }),
            !task.attachments.contains(where: {
                $0.url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
            })
        else { return }
        do {
            _ = try await provider.removeUnusedWorkspace(at: folder, in: project)
        } catch {
            task.addNotice(
                "The unused worktree is still on disk because cleanup failed. You can remove it from Git when ready.",
                isError: false)
        }
    }
}
