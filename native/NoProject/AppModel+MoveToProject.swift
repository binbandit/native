import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativePolicy
import TaskList

extension AppModel {
    /// A conversation with history reopens under the same agent session ID. An empty task prepares
    /// its replacement before closing the original, so a failed move keeps the draft available.
    func moveToProject(_ key: SessionKey, folder: URL, copyFiles: Bool) async throws {
        guard catalog.lookup(key)?.project == NoProjectLocation.id else {
            throw moveFailure("This task already has a project.")
        }
        let privateFolder = scratchTasks.folder(for: NoProjectLocation.key(key))
        if session(key) == nil { await loadSession(key) }
        // An unsent conversation reopens under a new agent ID. Its owned folder follows it.
        let opened =
            session(key)
            ?? sessions.loadedSessions.first {
                guard let privateFolder else { return false }
                return scratchTasks.folder(for: NoProjectLocation.key($0.key)) == privateFolder
            }
        guard let opened, let source = await loadedSession(opened.key), source.isProjectless else {
            throw moveFailure("The task couldn't be opened. Open it and try again.")
        }
        let key = source.key
        let isEmpty = !source.hasStarted && !source.hasSubmittedPrompt
        guard source.origin == .user, !source.isSubagent, !source.isEarlierConversation,
            source.phase == .idle, !source.hasQueuedPrompts, !source.needsApproval,
            !source.isChangingWorkspace, !source.isChangingAgent, !source.hasSubagents,
            !source.isRunningHiddenCommand, !source.isRetryScheduled, !source.isRestoringHistory
        else { throw moveFailure("Wait for this task and its agents to finish, then try again. Your draft is kept.") }
        if let reason = workspaceChangeBlock(source) { throw moveFailure(reason) }
        if let reason = modelChangeGoalBlock(source) { throw moveFailure(reason) }
        if let reason = coordinatorConversationBlock(for: source.key) { throw moveFailure(reason) }
        guard let runtime = await ensureRunning(for: key), (isEmpty || runtime.capabilities?.loadSession == true),
            runtime.capabilities?.closeSessions == true
        else {
            throw moveFailure(
                "This agent can't reopen its conversation in another folder. Your task and files are kept.")
        }
        guard PolicyCenter.shared.policy.agents.allows(key.agent.rawValue) else {
            throw moveFailure("Your organization doesn't allow this agent.")
        }
        guard let admitted = await admittedProjectFolder(folder) else {
            let message = actionFailure?.message ?? "This project folder isn't allowed."
            actionFailure = nil
            throw moveFailure(message)
        }
        guard !NoProjectLocation.contains(admitted),
            admitted.standardizedFileURL.resolvingSymlinksInPath() != NoProjectLocation.root
        else {
            throw moveFailure("Choose a project outside Native's private task files.")
        }
        // The validation above suspends for policy and startup. Recheck before sealing the draft.
        guard source.phase == .idle, !source.hasQueuedPrompts, !source.isChangingWorkspace,
            !pendingDeletionKeys.contains(key), !isArchived(key), sessions.session(key) === source
        else { throw moveFailure("The task changed while choosing a folder. Wait for it to finish and try again.") }
        guard (try? admitted.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw moveFailure("This folder is unavailable. Choose another project folder.")
        }
        source.isChangingWorkspace = true
        let draft = source.draft
        let attachments = source.attachments
        var copied: URL?
        var candidate: SessionModel?
        var didCloseSource = false
        do {
            try scratchTasks.reassign(source.cwd, to: NoProjectLocation.key(key))
            if copyFiles {
                let copy = try scratchTasks.copyingFiles(of: NoProjectLocation.key(key), into: admitted)
                copied = try await Task.detached(priority: .utility, operation: copy).value
            }
            guard sessions.session(key) === source, !pendingDeletionKeys.contains(key), !isArchived(key),
                source.phase == .idle, !source.hasQueuedPrompts
            else {
                throw moveFailure("The task changed while its files were being copied. Try again when it's ready.")
            }
            let target: SessionModel
            if isEmpty {
                target = try await launcher.start(on: runtime, cwd: admitted, project: nil, preparingModel: true)
                candidate = target
                target.isChangingWorkspace = true
                await target.adoptConfigChoices(of: source)
                await source.services.hooks.taskStarted(target, source)
                try scratchTasks.reassign(source.cwd, to: NoProjectLocation.key(target.key))
                try await closeForScratchCleanup(key)
                didCloseSource = true
            } else {
                try await closeForScratchCleanup(key)
                didCloseSource = true
                target = try await launcher.load(key, cwd: admitted, title: source.title, on: runtime)
                candidate = target
            }
            target.isChangingWorkspace = true
            guard let loaded = await loadedSession(target.key), loaded === target, loaded.phase == .idle,
                !loaded.isRestoringHistory, SessionFolder.isSame(loaded.cwd.folderPath, admitted.folderPath)
            else { throw moveFailure("The agent couldn't reopen the conversation in this folder.") }
            target.continuedTaskKey = source.taskPresentationKey
            source.attachmentReads.move(to: target)
            target.draft = draft
            target.attachments = attachments
            target.usesComposePresentation = source.usesComposePresentation
            let project = projects.add(admitted)
            if let title = titles.namedTitle(for: source.titleKey) { titles.rename(target.titleKey, to: title) }
            catalog.remove(key)
            ordering.replace(key, with: target.key)
            history.replace(key, with: target.key)
            taskPairs.replace(key, with: target.key)
            earlierConversations.replace(key, with: target.key)
            unsentSessions.forget(key)
            if isEmpty { unsentSessions.started(target.key, draft: draft) }
            catalog.add(
                SessionInfo(sessionId: target.id, cwd: admitted.folderPath, title: source.title, updatedAt: .now),
                for: target.agent.id, in: project.id)
            hosts.deviceWorkspaces?.routes[key] = nil
            target.isChangingWorkspace = false
            target.wantsComposerFocus = true
            if selection == key { selection = target.key }
            target.addNotice(
                "Moved to \(project.name). Your conversation continues here."
                    + (copied.map { " Task files were copied into \($0.lastPathComponent)." } ?? ""), isError: false)
        } catch {
            // Only our newly-created copy is rolled back. Never mutate originals or existing files.
            if let copied { try? FileManager.default.removeItem(at: copied) }
            if let candidate, sessions.session(candidate.key) === candidate {
                try? await closeForScratchCleanup(candidate.key)
            }
            if isEmpty { try? scratchTasks.reassign(source.cwd, to: NoProjectLocation.key(key)) }
            if didCloseSource {
                do {
                    let restored = try await launcher.load(key, cwd: source.cwd, title: source.title, on: runtime)
                    restored.draft = draft
                    restored.attachments = attachments
                    restored.usesComposePresentation = source.usesComposePresentation
                } catch {
                    source.isChangingWorkspace = false
                    sessions.register(source)
                    source.addNotice(
                        "Couldn't reopen the task. Its conversation and private files are kept. Restart the agent to continue.",
                        isError: true)
                }
            }
            source.isChangingWorkspace = false
            throw error
        }
    }

    /// Await the agent's close before deleting its files or changing its working directory.
    func closeForScratchCleanup(_ key: SessionKey) async throws {
        guard let source = sessions.session(key) else {
            if let client = runtimes.host {
                let held = try await client.sessions().first {
                    $0.agentID == key.agent.rawValue && $0.agentSessionID == key.id
                }
                guard let held else {
                    throw moveFailure("Couldn't confirm that this task closed. Its private files are kept.")
                }
                try await client.closeSessionConfirmed(held.id)
            } else if let runtime = agentRuntime(for: key), runtime.isReady {
                guard runtime.capabilities?.closeSessions == true, let connection = runtime.connection else {
                    throw moveFailure("The agent couldn't close this task. Its private files are kept.")
                }
                _ = try await connection.send(CloseSessionRequest(sessionId: key.id))
            } else {
                throw moveFailure("Couldn't confirm that this task closed. Its private files are kept.")
            }
            return
        }
        if let host = source.host {
            try await host.client.closeSessionConfirmed(host.id)
            sessions.hostSummaries[host.id] = nil
        } else {
            guard agentRuntime(for: key)?.capabilities?.closeSessions == true, let connection = source.connection else {
                throw moveFailure(
                    "The agent couldn't close this task. Its private files are kept. Restart the agent and retry.")
            }
            _ = try await connection.send(CloseSessionRequest(sessionId: key.id))
        }
        sessions.remove(source)
    }

    private func moveFailure(_ message: String) -> TaskWorkspaceSelectionError { TaskWorkspaceSelectionError(message) }
}
