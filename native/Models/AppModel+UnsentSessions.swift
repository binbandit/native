import ACP
import Foundation

// New sessions that never got a message (`UnsentSessions`). Their agents never saved them, so an
// empty one left behind would sit in the sidebar as "New Session" across launches with nothing to
// reopen. At launch the empty ones go; one left with a draft stays as "Draft: …" and opens as a fresh
// session that carries the draft on.
extension AppModel {
    /// Drops the sessions earlier runs left empty, before anything lists them. Internal only for
    /// AppModel.swift's init.
    func dropUnsentSessions() {
        let dropped = unsentSessions.removeAll { key, draft in
            draft == nil || !catalog.contains(key)
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
        guard sessions.session(key) == nil, let draft = unsentSessions.draft(for: key) else { return nil }
        let line = draft.prefix { !$0.isNewline }.trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? "Draft" : "Draft: \(line)"
    }

    /// Opens a session an earlier run left with only a draft: its agent never saved it, so a fresh
    /// session in the same folder takes its place in the sidebar, with the draft in its composer.
    /// Returns false when it isn't one.
    func reopenUnsent(_ key: SessionKey, info: SessionInfo, on runtime: AgentRuntime) async -> Bool {
        guard unsentSessions.draft(for: key) != nil else { return false }
        // Another load of it got here first and is reopening it.
        guard let draft = unsentSessions.claim(key) else { return true }
        let project = catalog.lookup(key)?.project
        do {
            let session = try await launcher.start(
                on: runtime, cwd: URL(filePath: info.cwd, directoryHint: .isDirectory), project: project)
            session.draft = draft
            catalog.swap(key, for: SessionInfo(sessionId: session.id, cwd: info.cwd, updatedAt: .now))
            ordering.replace(key, with: session.key)
            history.replace(key, with: session.key)
            unsentSessions.forget(key)
            unsentSessions.started(session.key)
            if selection == key {
                session.wantsComposerFocus = true
                selection = session.key
            }
        } catch {
            unsentSessions.release(key)
            openFailures[key] = SessionOpenFailure(error, agent: runtime.agent.displayName)
        }
        return true
    }
}
