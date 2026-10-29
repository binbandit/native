import ACP
import Foundation
import TaskList

// New sessions that never got a message (`UnsentSessions`). Their agents never saved them, so an
// empty one left behind would sit in the sidebar as "New Session" across launches with nothing to
// reopen. At launch the empty ones go; one left with a draft stays as "Draft: …" and opens as a fresh
// session that carries the draft on.
extension AppModel {
    /// Drops the sessions earlier runs left empty, before anything lists them. Internal only for
    /// AppModel.swift's init.
    func dropUnsentSessions() {
        let dropped = unsentSessions.removeAll { key, draft in
            (draft == nil && !sessions.services.modelContinuations.hasPending(key)
                && scratchTasks.folder(for: NoProjectLocation.key(key)) == nil
                && !hasPersistedDiffCommentDraft(for: key)) || !catalog.contains(key)
        }
        for key in dropped {
            catalog.remove(key)
        }
    }

    /// Saves every composer's draft at once, for when Native quits, and notes those of sessions still
    /// waiting for their first message.
    func keepDrafts() {
        sessions.services.drafts.save()
        unsentSessions.keepDrafts { sessions.session($0)?.draft }
    }

    /// A first message means the agent keeps the session from now on. Internal only for
    /// AppModel.swift, which hands each session event here.
    func noteSent(after event: SessionEvent) {
        guard case .promptSent(let context, _) = event, context.parentID == nil, let id = context.sessionID else {
            return
        }
        unsentSessions.sent(SessionKey(agent: context.agent, id: id))
    }

    /// "Draft: Fix the login form", for a session an earlier run left with only a draft.
    func unsentDraftTitle(for key: SessionKey) -> String? {
        guard sessions.session(key) == nil else { return nil }
        guard let draft = unsentSessions.draft(for: key) else {
            return hasPersistedDiffCommentDraft(for: key) ? "Draft" : nil
        }
        let line = PromptQuote.summary(draft).prefix { !$0.isNewline }.trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? "Draft" : "Draft: \(line)"
    }

    /// Opens a session an earlier run left with only a draft: its agent never saved it, so a fresh
    /// session in the same folder takes its place in the sidebar, with the draft in its composer.
    /// Returns false when it isn't one.
    func reopenUnsent(_ key: SessionKey, info: SessionInfo, on runtime: AgentRuntime) async -> Bool {
        let continuation = sessions.services.modelContinuations.hasPending(key)
        let privateFolder = scratchTasks.folder(for: NoProjectLocation.key(key))
        let privateDraft = privateFolder != nil
        guard unsentSessions.contains(key),
            unsentSessions.draft(for: key) != nil || continuation || privateDraft
                || hasPersistedDiffCommentDraft(for: key)
        else { return false }
        // Another load of it got here first and is reopening it.
        guard let draft = unsentSessions.claim(key, includingEmpty: true) else { return true }
        let project = catalog.lookup(key)?.project
        var prepared: SessionModel?
        do {
            let session = try await launcher.start(
                on: runtime, cwd: URL(filePath: info.cwd, directoryHint: .isDirectory), project: project,
                preparingModel: continuation)
            prepared = session
            if continuation {
                deletedSessions.insert(session.key)
                try await recoverAgentModel(key, in: session)
                deletedSessions.remove(session.key)
            }
            session.draft = draft
            if let privateFolder {
                try scratchTasks.reassign(privateFolder, to: NoProjectLocation.key(session.key))
                let previous = SessionTitles.Key(agent: key.agent, session: key.id)
                await session.adoptConfigChoices(titles.configChoices(for: previous))
                if let title = titles.namedTitle(for: previous) { titles.rename(session.titleKey, to: title) }
            }
            session.diffCommentEditors = sessions.services.drafts.commentEditors(for: key)
            session.unresolvedCommentPacket = sessions.services.drafts.commentDelivery(for: key)
            session.enforceDiffCommentRetention()
            catalog.swap(key, for: SessionInfo(sessionId: session.id, cwd: info.cwd, updatedAt: .now))
            ordering.replace(key, with: session.key)
            taskPairs.replace(key, with: session.key)
            history.replace(key, with: session.key)
            unsentSessions.forget(key)
            unsentSessions.started(session.key, draft: draft)
            if movingProjectlessTask == key { movingProjectlessTask = session.key }
            sessions.services.drafts.keep("", for: key)
            sessions.services.drafts.keepCommentEditors([], for: key)
            sessions.services.drafts.keepCommentDelivery(nil, for: key)
            if selection == key {
                session.wantsComposerFocus = true
                selection = session.key
            }
        } catch {
            if let prepared {
                deletedSessions.insert(prepared.key)
                discardAgentChange(prepared)
            }
            unsentSessions.release(key)
            openFailures[key] = SessionOpenFailure(error, agent: runtime.agent.displayName)
        }
        return true
    }

    private func hasPersistedDiffCommentDraft(for key: SessionKey) -> Bool {
        !sessions.services.drafts.commentEditors(for: key).isEmpty
            || sessions.services.drafts.commentDelivery(for: key) != nil
    }
}
