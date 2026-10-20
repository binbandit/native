import ACP
import Foundation

// Pinned tasks: a section above the projects, in the user's order. A pinned task shows only there.
extension AppModel {
    func isPinned(_ key: SessionKey) -> Bool {
        ordering.isPinned(key)
    }

    /// Pinned tasks in pin order, leaving out archived ones, ones being deleted and ones whose agent
    /// isn't running.
    var pinnedSessions: [SessionSummary] {
        ordering.pinned.compactMap { key in
            guard !archivedSessions.contains(key), !pendingDeletionKeys.contains(key),
                let listed = catalog.lookup(key), let runtime = agentRuntime(for: key)
            else { return nil }
            return SessionSummary(project: listed.project, agent: runtime.agent, info: listed.info)
        }
    }

    func setPinned(_ key: SessionKey, _ pinned: Bool, undoManager: UndoManager? = nil) {
        guard ordering.isPinned(key) != pinned else { return }
        let index = pinned ? nil : ordering.unpin(key)
        if pinned {
            ordering.pin(key)
        }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                if pinned {
                    model.setPinned(key, false, undoManager: undoManager)
                } else {
                    model.ordering.pin(key, at: index)
                    undoManager?.registerUndo(withTarget: model) { model in
                        MainActor.assumeIsolated { model.setPinned(key, false, undoManager: undoManager) }
                    }
                }
            }
        }
        undoManager?.setActionName(pinned ? "Pin Task" : "Unpin Task")
    }

    func movePinnedSessions(fromOffsets source: IndexSet, toOffset destination: Int) {
        ordering.movePinned(pinnedSessions.map(\.id), fromOffsets: source, toOffset: destination)
    }
}
