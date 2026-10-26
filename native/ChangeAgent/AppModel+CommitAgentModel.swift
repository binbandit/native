import ACP
import Foundation

extension AppModel {
    /// Publish only a confirmed selection. No working message is submitted here.
    func commitAgentModel(
        _ change: ComposerAgentChange, source: SessionModel, target: SessionModel, context: String
    ) {
        guard let project = catalog.lookup(source.key)?.project else { return }
        source.isModelChangeSource = true
        target.continuedTaskKey = source.taskPresentationKey
        titles.rename(target.titleKey, to: source.displayTitle)
        sessions.services.modelContinuations.prepare(context, for: target.key)
        if agentChangePlace(of: source) == .thisMac {
            deletedSessions.remove(target.key)
            unsentSessions.forget(target.key)
            catalog.add(
                SessionInfo(sessionId: target.id, cwd: source.cwd.folderPath, updatedAt: .now),
                for: target.agent.id, in: project)
        } else {
            publishRemoteAgentChange(target, in: project)
        }
        earlierConversations.record(target.key, after: source.key)
        earlierConversations.keep(target.key)
        moveAgentModelDraft(from: source, to: target)
        ordering.replace(source.key, with: target.key)
        taskPairs.replace(source.key, with: target.key)
        history.replace(source.key, with: target.key)
        if selection == source.key {
            selection = target.key
            target.wantsComposerFocus = true
        }
    }

    func undoAgentModel(_ change: ComposerAgentChange, source: SessionModel, target: SessionModel) {
        source.isModelChangeSource = false
        sessions.services.modelContinuations.remove(target.key)
        earlierConversations.undoSelection(target.key, restoring: source.key)
        moveAgentModelDraft(from: target, to: source)
        ordering.replace(target.key, with: source.key)
        taskPairs.replace(target.key, with: source.key)
        history.replace(target.key, with: source.key)
        if selection == target.key { selection = source.key; source.wantsComposerFocus = true }
        deletedSessions.insert(target.key)
        discardAgentChange(target)
    }

    private func moveAgentModelDraft(from source: SessionModel, to target: SessionModel) {
        target.draft = source.draft
        target.attachments = source.attachments
        target.quoteSelection = source.quoteSelection
        target.quoteSelectionSource = source.quoteSelectionSource
        source.draft = ""
        source.attachments = []
        source.quoteSelection = []
        source.quoteSelectionSource = nil
    }
}
