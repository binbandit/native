import ACP
import Foundation

// Session titles: what the sidebar shows, the user's renames (with undo), and naming the folder Native
// made for a task once it has a title.
extension AppModel {
    func title(for summary: SessionSummary) -> String {
        if let session = sessions.session(summary.id) {
            return session.displayTitle
        }
        return titles.title(for: SessionTitles.Key(agent: summary.agent.id, session: summary.info.sessionId), agentTitle: summary.info.title) ?? "New Session"
    }

    /// Lets the workspace provider name a task's workspace (its branch) after the task's first real
    /// title. That includes a task in the project's own folder, which in branch mode still gets
    /// its own provisional branch; the provider decides whether there's anything to rename.
    func workspaceGotTitle(_ event: TitleEvent) async {
        guard let provider = taskWorkspaces, !titledWorkspaces.contains(event.key),
              let projectID = catalog.lookup(event.key)?.project, let project = projects.project(projectID)
        else { return }
        titledWorkspaces.insert(event.key)
        await provider.taskDidGetTitle(event.title, workspace: event.folder, in: project)
    }

    /// Gives the session the user's own title; an empty one goes back to the automatic title.
    /// With an undo manager, ⌘Z restores the title exactly, automatic or the user's.
    func rename(_ key: SessionKey, to title: String, undoManager: UndoManager? = nil) {
        let previous = userTitle(for: key) ?? ""
        titles.rename(SessionTitles.Key(agent: key.agent, session: key.id), to: title)
        if let session = sessions.session(key), let newTitle = userTitle(for: key) {
            Task { await workspaceGotTitle(TitleEvent(key: key, folder: session.cwd, title: newTitle)) }
        }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.rename(key, to: previous, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Rename Session")
    }

    /// The title the user gave the session, or nil while it goes by an automatic one.
    func userTitle(for key: SessionKey) -> String? {
        titles.userTitle(for: SessionTitles.Key(agent: key.agent, session: key.id))
    }
}
